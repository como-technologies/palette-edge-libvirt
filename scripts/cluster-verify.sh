#!/usr/bin/env bash
# Test that the cluster works.
#
# This is the test suite of the repository. `just cluster-up` returns 0 when
# Palette reports that it made the cluster, and that is not the same as a
# cluster that operates. Each test below is a condition that a person would
# check by hand, and one of them is a regression test for a fault that passed
# every exit code:
#
#   the pod range. A pod range that holds the cluster subnet gives no NAT to
#   the gateway, so a pod resolves no name. Every node stays Ready, kubectl
#   answers, and the cluster is useless. See docs/src/cluster-profile.md.
#
# The script makes no change to the cluster. It prints ok or FAIL for each test
# and stops with a failure code if one test fails.
#
# The kubeconfig comes from the OpenTofu state, through `cluster.sh kubeconfig`.
# It holds administrator credentials, so it goes to a file with mode 0600 in a
# private directory, and the trap removes it.
#
# Env: CLUSTER CONTROL_COUNT WORKER_COUNT K8S_VERSION POD_CIDR CLUSTER_VIP
#      PALETTE_PROJECT
#
#   cluster-verify.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

here="$(dirname "${BASH_SOURCE[0]}")"

need_project
need kubectl

fail=0

# check <label> <yes|no> <detail-when-ok> <detail-when-failed>
check() {
	local label="$1" ok="$2" good="${3:-}" bad="${4:-}"
	if [ "$ok" = yes ]; then
		printf '  ok    %-24s %s\n' "$label" "$good"
	else
		printf '  FAIL  %-24s %s\n' "$label" "$bad"
		fail=1
	fi
}

# --- the kubeconfig ---------------------------------------------------------

work="$(mktemp -d)"
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT

export KUBECONFIG="$work/kubeconfig"

info "cluster $CLUSTER in project $PALETTE_PROJECT"

# cluster.sh prints its own message for a project with no cluster layer.
"$here/cluster.sh" kubeconfig >"$KUBECONFIG" 2>"$work/err" || {
	cat "$work/err" >&2
	die "cannot read the kubeconfig, so there is nothing to test.
     To make the cluster:  just cluster-up"
}
chmod 600 "$KUBECONFIG"
[ -s "$KUBECONFIG" ] || die "the kubeconfig is empty. To make the cluster: just cluster-up"

# --- the API server ---------------------------------------------------------

info "the API server"

if nodes_json="$(kubectl get nodes -o json 2>"$work/err")"; then
	check "connection" yes "$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')"
else
	check "connection" no "" "$(head -n1 "$work/err")"
	printf '\n'
	die "the cluster does not answer at $(kubectl config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null).
     The address is the virtual one that kube-vip claims. Test the route:
       ping -c1 ${CLUSTER_VIP:-the VIP}
     See docs/src/network.md."
fi

# --- the nodes --------------------------------------------------------------

info "the nodes"

want_nodes=$(("${CONTROL_COUNT:-1}" + "${WORKER_COUNT:-2}"))

read -r total ready < <(printf '%s' "$nodes_json" | python3 -c '
import json, sys
items = json.load(sys.stdin).get("items") or []
ready = 0
for node in items:
    for cond in (node.get("status") or {}).get("conditions") or []:
        if cond.get("type") == "Ready" and cond.get("status") == "True":
            ready += 1
print(len(items), ready)
')

if [ "$total" -eq "$want_nodes" ]; then
	check "count" yes "$total node(s), and the topology asks for $want_nodes"
else
	check "count" no "" "$total node(s), and the topology asks for $want_nodes"
fi

if [ "$ready" -eq "$total" ] && [ "$total" -gt 0 ]; then
	check "Ready" yes "every node is Ready"
else
	check "Ready" no "" "$ready of $total node(s) are Ready. To see them: kubectl get nodes"
fi

# The pack pins the version, so a node that runs another one means the profile
# and the cluster disagree.
if [ -n "${K8S_VERSION:-}" ]; then
	bad_version="$(printf '%s' "$nodes_json" | python3 -c '
import json, sys, os
want = "v" + os.environ["K8S_VERSION"].split("-")[0]
out = []
for node in json.load(sys.stdin).get("items") or []:
    got = ((node.get("status") or {}).get("nodeInfo") or {}).get("kubeletVersion") or "?"
    if not got.startswith(want):
        out.append(node["metadata"]["name"] + "=" + got)
print(" ".join(out))
')"
	if [ -z "$bad_version" ]; then
		check "version" yes "every node runs v${K8S_VERSION}"
	else
		check "version" no "" "K8S_VERSION is $K8S_VERSION and these differ: $bad_version"
	fi
fi

# --- the pod range ----------------------------------------------------------
#
# The regression test. `edge-k8s` defaults to a pod range that holds the cluster
# subnet, and cluster-profile.tf replaces it. A replace that matches nothing is
# silent, so test the result on the cluster and not in the values.

info "the pod range"

pod_cidr="${POD_CIDR:-10.244.0.0/16}"
pod_prefix="${pod_cidr%%.*}.$(printf '%s' "${pod_cidr#*.}" | cut -d. -f1)"

bad_cidr="$(POD_PREFIX="$pod_prefix" python3 -c '
import json, sys, os
prefix = os.environ["POD_PREFIX"] + "."
out = []
for node in json.load(sys.stdin).get("items") or []:
    got = (node.get("spec") or {}).get("podCIDR") or "none"
    if not got.startswith(prefix):
        out.append(node["metadata"]["name"] + "=" + got)
print(" ".join(out))
' <<<"$nodes_json")"

if [ -z "$bad_cidr" ]; then
	check "podCIDR" yes "every node takes a range inside $pod_cidr"
else
	check "podCIDR" no "" "POD_CIDR is $pod_cidr and these differ: $bad_cidr"
fi

# The cluster subnet must not hold the pod range. This is the condition that
# cluster.sh refuses before a build, tested here on the object itself.
subnet_prefix="${CLUSTER_SUBNET:-192.168.140}"
subnet_prefix="${subnet_prefix%%.*}.$(printf '%s' "${subnet_prefix#*.}" | cut -d. -f1)"
if [ "$pod_prefix" != "$subnet_prefix" ]; then
	check "no overlap" yes "the pod range holds no address of the cluster subnet"
else
	check "no overlap" no "" "$pod_cidr holds the cluster subnet. Calico gives no NAT inside its own pool."
fi

# --- the packs --------------------------------------------------------------

info "the packs"

pods_json="$(kubectl get pods --all-namespaces -o json 2>/dev/null || echo '{}')"

# pods_ready <label> <name-fragment>: test that at least one pod whose name
# holds the fragment runs, and that every one of them is Ready.
pods_ready() {
	local label="$1" want="$2" result
	result="$(WANT="$want" python3 -c '
import json, sys, os
want = os.environ["WANT"]
total = ready = 0
for pod in json.load(sys.stdin).get("items") or []:
    if want not in pod["metadata"]["name"]:
        continue
    total += 1
    conds = (pod.get("status") or {}).get("conditions") or []
    if any(c.get("type") == "Ready" and c.get("status") == "True" for c in conds):
        ready += 1
print(total, ready)
' <<<"$pods_json")"
	local total ready
	total="${result% *}"
	ready="${result#* }"
	if [ "$total" -gt 0 ] && [ "$ready" -eq "$total" ]; then
		check "$label" yes "$ready of $total pod(s) Ready"
	elif [ "$total" -eq 0 ]; then
		check "$label" no "" "no pod of this kind runs"
	else
		check "$label" no "" "$ready of $total pod(s) Ready"
	fi
}

pods_ready "calico" "calico"
pods_ready "coredns" "coredns"

# The CSI pack makes the default StorageClass. A cluster with no default class
# leaves every PersistentVolumeClaim pending.
default_sc="$(kubectl get storageclass -o json 2>/dev/null | python3 -c '
import json, sys
for item in json.load(sys.stdin).get("items") or []:
    ann = (item["metadata"].get("annotations") or {})
    if ann.get("storageclass.kubernetes.io/is-default-class") == "true":
        print(item["metadata"]["name"])
' | head -n1 || true)"

if [ -n "$default_sc" ]; then
	check "default storage" yes "$default_sc"
else
	check "default storage" no "" "no StorageClass is the default one"
fi

# --- a pod resolves a name --------------------------------------------------
#
# The test that the pod range regression needs. Everything above passes on a
# cluster whose pods reach no name server at all.

info "a pod resolves a name"

dns_pod="verify-dns-$$"
if kubectl run "$dns_pod" \
	--image=busybox:1.36 --restart=Never --rm --attach --quiet \
	--command --timeout=180s -- \
	nslookup kubernetes.default.svc.cluster.local >"$work/dns" 2>&1; then
	check "cluster DNS" yes "a pod resolved kubernetes.default"
else
	check "cluster DNS" no "" "a pod resolved no name. See $pod_cidr and docs/src/cluster-profile.md"
	sed 's/^/        /' "$work/dns" | head -n 8 >&2 || true
	kubectl delete pod "$dns_pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
fi

# --- the result -------------------------------------------------------------

printf '\n'
if [ "$fail" -eq 0 ]; then
	info "the cluster works"
else
	die "the cluster does not pass every test. See docs/src/troubleshooting.md."
fi
