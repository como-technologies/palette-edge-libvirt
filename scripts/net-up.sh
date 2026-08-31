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

# A session daemon makes no network: a bridge, NAT, and dnsmasq all need root.
# The lab of a session therefore uses the bridge of a system network that root
# made one time, and `just runner-setup` is what makes it.
#
# Test the bridge rather than the network. The session connection cannot see a
# system network at all, and the bridge is a device that every account reads.
if libvirt_session; then
	if [ -d "/sys/class/net/$bridge" ]; then
		skip "session mode uses the bridge $bridge, which exists"
		exit 0
	fi
	die "session mode needs the bridge $bridge, and there is none.
     A session makes no network, so root makes the network one time and the
     session domains take its bridge.
     Run:  just runner-setup"
fi
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
