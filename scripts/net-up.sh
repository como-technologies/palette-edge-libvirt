#!/usr/bin/env bash
# Create and start the isolated NAT network of the cluster.
#
# This script is idempotent. It defines the network only if the network is
# absent. It starts the network only if the network is inactive.
#
# Env: NETWORK CLUSTER SUBNET BUILD_DIR

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${NETWORK:?}" "${CLUSTER:?}" "${SUBNET:?}" "${BUILD_DIR:?}"

# The name reaches libvirt and Palette, and each one has a rule. Test both here,
# at the first recipe that uses the name: libvirt reports its own fault as
# "Numerical result out of range" only when the network starts, and Palette
# reports its own minutes later, when `just cluster-up` makes the cluster.
require_cluster_name "$CLUSTER"
bridge="br-$CLUSTER"
root="$(repo_root)"

need virsh
mkdir -p "$BUILD_DIR"

if virsh net-info "$NETWORK" >/dev/null 2>&1; then
	skip "network $NETWORK is already defined"
else
	xml="$BUILD_DIR/$NETWORK.xml"
	sed -e "s/@NAME@/$NETWORK/g" \
			-e "s/@BRIDGE@/$bridge/g" \
			-e "s/@SUBNET@/$SUBNET/g" \
		"$root/templates/network.xml" >"$xml"
	virsh net-define "$xml" >/dev/null
	info "defined network $NETWORK on $SUBNET.0/24, bridge $bridge"
fi

if [ "$(virsh net-info "$NETWORK" | awk '/^Active:/ { print $2 }')" = "yes" ]; then
	skip "network $NETWORK is already active"
else
	virsh net-start "$NETWORK" >/dev/null
	info "started network $NETWORK"
fi

virsh net-autostart "$NETWORK" >/dev/null
virsh net-info "$NETWORK"
