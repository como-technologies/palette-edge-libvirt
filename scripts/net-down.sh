#!/usr/bin/env bash
# Stop and remove the cluster network.
#
# This script is idempotent. It reports a skip if the network is absent.
#
# Give FORCE=1 to remove the network while a domain still uses it.
#
# Env: NETWORK FORCE

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${NETWORK:?}"
need virsh

if ! virsh net-info "$NETWORK" >/dev/null 2>&1; then
	skip "network $NETWORK is absent"
	exit 0
fi

# libvirt does NOT refuse to remove a network that a domain uses. It stops the
# bridge and reports success, and the domain keeps running with no way to reach
# anything. The host then never gets an address and never registers, and the
# only symptom is a host that waits for ever.
#
# An earlier version tested the exit code of net-destroy for this. That code is
# always 0, so the test never fired.
mapfile -t users < <(domains_using_network "$NETWORK")
if [ "${#users[@]}" -gt 0 ] && [ "${FORCE:-0}" != "1" ]; then
	die "network $NETWORK carries ${#users[@]} domain(s):
       ${users[*]}
     libvirt would remove it and leave each one with a dead bridge.
     Remove the machines first:  just infra-down
     To remove the network anyway:  FORCE=1 just net-down"
fi

if [ "$(virsh net-info "$NETWORK" | awk '/^Active:/ { print $2 }')" = "yes" ]; then
	virsh net-destroy "$NETWORK" >/dev/null ||
		die "cannot stop network $NETWORK. To see what holds it: just ls"
	info "stopped network $NETWORK"
fi

virsh net-undefine "$NETWORK" >/dev/null
info "removed network $NETWORK"
