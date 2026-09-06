#!/usr/bin/env bash
# Open the Headlamp web interface that the add-on profile installed.
#
# The service is a ClusterIP on port 443, so nothing outside the cluster reaches
# it. `kubectl port-forward` carries the connection through the API server,
# which the workstation already reaches at the virtual address of the control
# plane, so the cluster needs no ingress controller and no load balancer
# address.
#
# There is no sign-in. The add-on profile sets
# `unsafeUseServiceAccountToken: true` in the pack values, so Headlamp uses the
# service account of its own pod, which the chart binds to cluster-admin. See
# terraform/addon-profile.tf for why the sign-in of this pack cannot complete
# over a port forward.
#
# THE PORT FORWARD IS THE GATE. It needs the administrator kubeconfig of the
# cluster, and that comes from the OpenTofu state of this project. A person who
# can run this recipe already holds every permission that the page offers.
#
# The kubeconfig holds administrator credentials, so it goes to a file with
# mode 0600 in a private directory, and the trap removes both.
#
# Env: CLUSTER DASHBOARD_PORT PALETTE_PROJECT
#
#   dashboard.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

here="$(dirname "${BASH_SOURCE[0]}")"

# The names come from the values of the headlamp pack. The chart sets
# fullnameOverride, so the namespace, the service, the deployment, and the
# service account all carry the same name.
namespace="headlamp"
service="headlamp"
port="${DASHBOARD_PORT:-8443}"

need_project
need kubectl

# --- nothing else may hold the port -----------------------------------------
#
# Test the port BEFORE the token. `kubectl port-forward` fails with "address
# already in use" after this script has printed a token, and a person then has
# a token, an error, and a page that answers on the port from an older forward.
# That older forward carries an older token, so the sign-in fails and the cause
# is two commands back.
if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
	exec 3<&-
	die "something already answers on port $port of this workstation.
     It is usually a port forward from an earlier run of this recipe that did
     not stop. Find it and end it:
       pgrep -af 'kubectl port-forward'
     Or use another port:
       DASHBOARD_PORT=9443 just dashboard"
fi

# --- the kubeconfig ---------------------------------------------------------

work="$(mktemp -d)"

# cleanup: end the port forward, then remove the credentials.
#
# Not `exec kubectl`: the kubeconfig is in this directory and kubectl reads it
# for as long as the forward runs, so this shell must stay to remove it. A
# child of this shell outlives it when the shell takes a signal that the child
# does not, and an orphan port forward holds the port and answers there with a
# forward to an older cluster. Kill it by name here.
forward=""
cleanup() {
	[ -z "$forward" ] || kill "$forward" 2>/dev/null || true
	rm -rf "$work"
}
chmod 700 "$work"
trap cleanup EXIT INT TERM

export KUBECONFIG="$work/kubeconfig"

"$here/cluster.sh" kubeconfig >"$KUBECONFIG" 2>"$work/err" || {
	cat "$work/err" >&2
	die "cannot read the kubeconfig, so there is no cluster to open.
     To make the cluster:  just cluster-up"
}
chmod 600 "$KUBECONFIG"
[ -s "$KUBECONFIG" ] || die "the kubeconfig is empty. To make the cluster: just cluster-up"

# --- the dashboard must be there --------------------------------------------
#
# `kubectl port-forward` on an absent service prints "services
# \"kubernetes-dashboard\" not found" and names no correction. Palette installs
# the add-on profile after the cluster answers, so the usual reason is that the
# install is not finished yet.

kubectl get service "$service" -n "$namespace" >/dev/null 2>&1 ||
	die "the cluster runs no $service service in the namespace $namespace.
     $service is what the add-on profile installs.
     Palette installs the add-on profile after the cluster answers, so this
     is normal for some minutes after a build.
     To see the state of the pack:  just cluster-show
     To test the whole cluster:     just cluster-verify"

# --- open it ----------------------------------------------------------------

info "Headlamp on cluster ${CLUSTER:-} in project $PALETTE_PROJECT"
printf '\n'
printf '  URL     https://localhost:%s\n' "$port"
printf '  There is no sign-in. Headlamp uses the service account of its own\n'
printf '  pod, and that account holds cluster-admin on this cluster.\n\n'
printf '  The certificate is the one the chart makes for itself, so the browser\n'
printf '  reports it as untrusted. That is expected inside this lab.\n'
printf '  Press ctrl-c to close the connection.\n\n'

status=0
kubectl port-forward -n "$namespace" "service/$service" "$port:443" &
forward=$!
wait "$forward" || status=$?
forward=""

# 130 is ctrl-c and 143 is a stop signal. Both are how a person closes this
# recipe. Anything else is a fault.
case "$status" in
0 | 130 | 143) ;;
*)
	die "the port forward stopped with code $status.
     To test the cluster itself:  just cluster-verify"
	;;
esac
