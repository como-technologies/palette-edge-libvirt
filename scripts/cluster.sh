#!/usr/bin/env bash
# Run OpenTofu for the cluster layer of one project.
#
# This is the only place that calls `tofu`. Every cluster recipe passes through
# it, so the state path, the credentials, and the host list are computed one
# time and in one way:
#
#   the state          ~/.local/state/palette-edge-libvirt/<project>/
#   the credentials    the API key file, never a variable and never a file
#   the hosts          the topology, the same names that `just ls` prints
#
# The state names the cluster profile and the cluster that OpenTofu made. It is
# not a cache, and losing it means Palette holds objects that no recipe can
# remove. It therefore lives in the XDG state directory: never in the checkout,
# never in the module, and never in the current directory. `TF_DATA_DIR` sends
# the provider files to the same place.
#
# The state also holds the administrator kubeconfig of the cluster, so the
# directory is mode 0700 and each file in it is mode 0600.
#
# Env: CLUSTER CONTROL_COUNT WORKER_COUNT CLUSTER_SUBNET CLUSTER_VIP POD_CIDR
#      OS_PACK_VERSION K8S_VERSION CNI_VERSION CSI_VERSION
#      PALETTE_PROJECT PALETTE_ENDPOINT PALETTE_VIP_SKIP
#
#   cluster.sh plan
#   cluster.sh apply
#   cluster.sh destroy
#   cluster.sh output
#   cluster.sh kubeconfig

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

action="${1:?give an action: plan, apply, destroy, output, or kubeconfig}"
: "${CLUSTER:?}"

need curl
need python3

# Resolve the API key before any pipeline runs. die() inside a pipeline stops
# only the subshell, and the caller then fails on empty input.
need_api_key
need_project

state="$(project_state_dir)"

# A project that never made a cluster layer has no state file. `just nuke`
# reaches `cluster-down` on such a project, and that must not need OpenTofu at
# all. Answer before the test for the command.
if [ ! -s "$state/terraform.tfstate" ]; then
	case "$action" in
	destroy | output)
		skip "project $PALETTE_PROJECT has no cluster layer"
		exit 0
		;;
	kubeconfig)
		die "project $PALETTE_PROJECT has no cluster layer. To make one: just cluster-up"
		;;
	esac
fi

command -v tofu >/dev/null 2>&1 ||
	die "OpenTofu is not installed. Run: just tofu-install"

# A state file carries the version of OpenTofu that wrote it, and a newer
# version refuses to read it back. Report the difference, and do not stop: a
# workstation that packages its own OpenTofu is a reasonable choice.
if [ -n "${TOFU_VERSION:-}" ]; then
	have="$(tofu version 2>/dev/null | head -n1 | sed -n 's/^OpenTofu v\([0-9][^ ]*\).*/\1/p')"
	[ "$have" = "$TOFU_VERSION" ] ||
		warn "this is OpenTofu $have and the pinned version is $TOFU_VERSION.
         To install the pinned one: just tofu-install"
fi

module="$(repo_root)/terraform"

mkdir -p "$state"
chmod 700 "$state"

# --- the names of the hosts -------------------------------------------------

# The topology gives the names, and `host-up` makes one domain for each. The
# libvirt domain name and the Palette host name are the same, so this list
# reaches both sides.
control=()
worker=()
for i in $(seq 1 "${CONTROL_COUNT:-1}"); do control+=("${CLUSTER}-cp-$i"); done
for i in $(seq 1 "${WORKER_COUNT:-2}"); do worker+=("${CLUSTER}-wk-$i"); done

# json_list: print a list of strings as a JSON array. OpenTofu reads a
# TF_VAR_ value for a list variable as a literal, so this is the shape it wants.
json_list() {
	python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"
}

# --- the credentials and the variables --------------------------------------

# The provider reads the key from the environment. It is never a variable, so it
# reaches no state file and no plan file.
SPECTROCLOUD_HOST="$(palette_endpoint)"
TF_VAR_control_plane_hosts="$(json_list "${control[@]}")"
TF_VAR_worker_hosts="$(json_list "${worker[@]}")"

export SPECTROCLOUD_APIKEY="$PALETTE_API_KEY"
export SPECTROCLOUD_HOST

export TF_DATA_DIR="$state/tofu"
export TF_IN_AUTOMATION=1

export TF_VAR_palette_project="$PALETTE_PROJECT"
export TF_VAR_cluster_name="$CLUSTER"
export TF_VAR_control_plane_hosts
export TF_VAR_worker_hosts
export TF_VAR_vip="${CLUSTER_VIP:-}"
[ -z "${POD_CIDR:-}" ] || export TF_VAR_pod_cidr="$POD_CIDR"
[ -z "${OS_PACK_VERSION:-}" ] || export TF_VAR_os_pack_version="$OS_PACK_VERSION"
[ -z "${K8S_VERSION:-}" ] || export TF_VAR_k8s_version="$K8S_VERSION"
[ -z "${CNI_VERSION:-}" ] || export TF_VAR_cni_version="$CNI_VERSION"
[ -z "${CSI_VERSION:-}" ] || export TF_VAR_csi_version="$CSI_VERSION"

# --- the checks that only a build needs -------------------------------------
#
# require_cluster_name is in lib.sh, because both layers need the same name.
# net-up.sh runs it for the layer below, so a name that Palette refuses stops
# `just infra-up` instead of `just cluster-up` four minutes later.

# require_vip: stop unless the seed ISO and the cluster agree about the virtual
# address.
#
# Palette refuses a cluster that gives no control plane endpoint, and kube-vip
# answers at that address only when the seed enabled it. A cluster that names an
# address that nothing claims builds for an hour and then fails.
#
# Only a build needs this. A teardown must run even when the pair disagrees.
require_vip() {
	[ -n "${CLUSTER_VIP:-}" ] ||
		die "CLUSTER_VIP is empty, and Palette needs a control plane endpoint.
     Use a free address of the cluster subnet, below the DHCP pool, for
     example ${CLUSTER_SUBNET:-192.168.140}.10. See docs/src/network.md."

	[ "${PALETTE_VIP_SKIP:-false}" != "true" ] ||
		die "PALETTE_VIP_SKIP is true, so each seed ISO told its host to skip
     kube-vip, and nothing answers at $CLUSTER_VIP.
     Set PALETTE_VIP_SKIP=false in the project file, then build the machines
     again:  just seed-clean && just infra-down && just infra-up"
}

# require_pod_cidr: stop when the pod range holds the cluster subnet.
#
# Calico gives no NAT to a destination inside its own pool. A pod that asks the
# gateway of the cluster network for DNS then gets no answer, and the cluster
# waits for a name that it cannot resolve. The test compares only the first two
# numbers, which is what a /16 pod range decides.
require_pod_cidr() {
	local pod="${POD_CIDR:-10.244.0.0/16}" subnet="${CLUSTER_SUBNET:-192.168.140}"
	[ "${pod%%.*}.$(printf '%s' "${pod#*.}" | cut -d. -f1)" != \
		"${subnet%%.*}.$(printf '%s' "${subnet#*.}" | cut -d. -f1)" ] ||
		die "POD_CIDR is $pod and CLUSTER_SUBNET is ${subnet}.0/24, and the first
     holds the second. Calico gives no NAT inside its own pool, so the pods
     cannot reach the gateway of the cluster network.
     Give POD_CIDR a range that holds neither the cluster subnet nor the
     address of your workstation, for example 10.244.0.0/16."
}

# --- the state --------------------------------------------------------------

# state_has_resources: return 0 when the state file names an object that
# OpenTofu made. An empty state means this project has no cluster layer.
state_has_resources() {
	[ -s "$state/terraform.tfstate" ] || return 1
	python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if (data.get("resources") or []) else 1)
' "$state/terraform.tfstate"
}

# The state file holds the administrator kubeconfig of the cluster. Take the
# group and the world off it.
#
# Only the files of the directory itself. TF_DATA_DIR is below it and holds the
# provider, and a provider that OpenTofu cannot execute stops every run.
protect_state() {
	find "$state" -maxdepth 1 -type f -exec chmod 600 {} + 2>/dev/null || true
}
trap protect_state EXIT

# --- the hosts must be registered -------------------------------------------

# require_ready_hosts: stop unless Palette holds a usable record for each name.
#
# OpenTofu reads one appliance data source for each host, and its own message
# for an absent host does not say what to do about it. This one does. The test
# costs one request.
#
# Two states are usable, and the difference matters:
#
#   ready    the host registered and joins no cluster
#   in-use   the host is in a cluster
#
# `in-use` is correct for every run after the first: a second `cluster-up` and
# every `cluster-plan` see the hosts of the cluster that they made. It is wrong
# when this project has no cluster layer, because the host then belongs to some
# other cluster and this one must not take it.
require_ready_hosts() {
	# Not `state`: that name holds the path of the state directory, and a local
	# of the same name would hide it from state_has_resources below.
	local uid states missing=() taken=() name host_state

	uid="$(project_uid "$PALETTE_PROJECT")"
	[ -n "$uid" ] || die "project $PALETTE_PROJECT does not exist in this tenant.
     To see the names: just palette-projects"

	body="$(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid")"
	states="$(printf '%s' "$body" | python3 -c '
import json, sys
for host in json.load(sys.stdin).get("items") or []:
    print(host["metadata"]["name"], (host.get("status") or {}).get("state") or "unknown")
')"

	for name in "${control[@]}" "${worker[@]}"; do
		host_state="$(printf '%s\n' "$states" | awk -v n="$name" '$1 == n { print $2 }')"
		case "$host_state" in
		ready) ;;
		in-use) state_has_resources || taken+=("$name") ;;
		*) missing+=("$name") ;;
		esac
	done

	# A name with no record falls in one of two classes, and the correction is
	# not the same for both. A machine that does not exist needs `infra-up`. A
	# machine that runs and holds no record already had its chance: the agent
	# installs one time, so it never registers again by itself, and `infra-up`
	# would skip the domain and then wait for the whole timeout.
	if [ "${#missing[@]}" -gt 0 ]; then
		local absent=() stale=()
		for name in "${missing[@]}"; do
			if command -v virsh >/dev/null 2>&1 && have_domain "$name"; then
				stale+=("$name")
			else
				absent+=("$name")
			fi
		done

		[ "${#absent[@]}" -eq 0 ] || die "these host(s) have no machine in project $PALETTE_PROJECT:
       ${absent[*]}
     The cluster layer builds on the layer below it. Run: just infra-up"

		die "these machine(s) run and hold no record in project $PALETTE_PROJECT:
       ${stale[*]}
     The agent installs one time, so a machine that lost its record does not
     register again. Build those machines again:
       just infra-down && just infra-up
     To see what one of them did:  just host-status <host>"
	fi

	[ "${#taken[@]}" -eq 0 ] || die "these host(s) are in a cluster already, and this project has
     no cluster layer of its own:
       ${taken[*]}
     A host belongs to one cluster. Build the machines again:
       just infra-down && just infra-up"
}

# --- run OpenTofu -----------------------------------------------------------

# `init` is idempotent and fast after the first run. `-reconfigure` keeps it
# quiet when the state path moves, for example when PEL_STATE_DIR changes.
tofu -chdir="$module" init -input=false -reconfigure \
	-backend-config="path=$state/terraform.tfstate" >/dev/null ||
	die "tofu init failed in $(short_path "$module")"

case "$action" in
plan)
	require_cluster_name "$CLUSTER"
	require_vip
	require_pod_cidr
	require_ready_hosts
	tofu -chdir="$module" plan -input=false
	;;
apply)
	require_cluster_name "$CLUSTER"
	require_vip
	require_pod_cidr
	require_ready_hosts
	info "build the cluster layer of project $PALETTE_PROJECT"
	info "Palette installs four packs on ${#control[@]} control and ${#worker[@]} worker node(s). That took about 11 minutes for 1 and 2."
	tofu -chdir="$module" apply -input=false -auto-approve
	info "the cluster is up. To see it: just cluster-show"
	;;
destroy)
	if ! state_has_resources; then
		skip "project $PALETTE_PROJECT has no cluster layer"
		exit 0
	fi
	info "remove the cluster and the cluster profile of project $PALETTE_PROJECT"
	tofu -chdir="$module" destroy -input=false -auto-approve
	info "the hosts and the machines stay. To remove those: just infra-down"
	;;
output)
	if ! state_has_resources; then
		skip "project $PALETTE_PROJECT has no cluster layer. To make one: just cluster-up"
		exit 0
	fi
	tofu -chdir="$module" output
	;;
kubeconfig)
	state_has_resources ||
		die "project $PALETTE_PROJECT has no cluster layer. To make one: just cluster-up"
	tofu -chdir="$module" output -raw kubeconfig
	;;
*)
	die "unknown action '$action'. Use plan, apply, destroy, output, or kubeconfig."
	;;
esac
