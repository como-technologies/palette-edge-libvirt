#!/usr/bin/env bash
# Stop and remove the lab network.
#
# This script is idempotent. It reports a skip if the network is absent.
#
# Env: NETWORK

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${NETWORK:?}"
need virsh

if ! virsh net-info "$NETWORK" >/dev/null 2>&1; then
	skip "network $NETWORK is absent"
	exit 0
fi

# A running VM holds the bridge. Report this instead of a raw libvirt error.
if [ "$(virsh net-info "$NETWORK" | awk '/^Active:/ { print $2 }')" = "yes" ]; then
	virsh net-destroy "$NETWORK" >/dev/null ||
		die "cannot stop $NETWORK. A VM still uses it. Run: just cluster-down"
	info "stopped network $NETWORK"
fi

virsh net-undefine "$NETWORK" >/dev/null
info "removed network $NETWORK"
