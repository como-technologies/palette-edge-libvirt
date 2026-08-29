#!/usr/bin/env bash
# Create and start the isolated NAT network of the lab.
#
# This script is idempotent. It defines the network only if the network is
# absent. It starts the network only if the network is inactive.
#
# Env: NETWORK SUBNET BUILD_DIR

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${NETWORK:?}" "${SUBNET:?}" "${BUILD_DIR:?}"
root="$(repo_root)"

need virsh
mkdir -p "$BUILD_DIR"

if virsh net-info "$NETWORK" >/dev/null 2>&1; then
	skip "network $NETWORK is already defined"
else
	xml="$BUILD_DIR/$NETWORK.xml"
	sed -e "s/@NAME@/$NETWORK/g" -e "s/@SUBNET@/$SUBNET/g" \
		"$root/templates/network.xml" >"$xml"
	virsh net-define "$xml" >/dev/null
	info "defined network $NETWORK on $SUBNET.0/24"
fi

if [ "$(virsh net-info "$NETWORK" | awk '/^Active:/ { print $2 }')" = "yes" ]; then
	skip "network $NETWORK is already active"
else
	virsh net-start "$NETWORK" >/dev/null
	info "started network $NETWORK"
fi

virsh net-autostart "$NETWORK" >/dev/null
virsh net-info "$NETWORK"
