#!/usr/bin/env bash
# Print the lease address for a host.
#
# The edge images do not run qemu-guest-agent, so `virsh domifaddr` comes back
# empty; the DHCP lease on the lab network is the reliable source.
#
#   host-ip.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"

mac="$(virsh domiflist "$name" | awk 'NF >= 5 && $3 != "-" { print $5 }' | head -n1)"
[ -n "$mac" ] || die "no interface found on $name"

net="$(virsh domiflist "$name" | awk 'NF >= 5 && $2 == "network" { print $3 }' | head -n1)"
[ -n "$net" ] || die "$name is not attached to a libvirt network"

lease="$(virsh net-dhcp-leases "$net" | awk -v m="$mac" '$3 == m { print $5 }' | cut -d/ -f1 | head -n1)"

if [ -z "$lease" ]; then
	die "no DHCP lease for $name ($mac) on $net yet -- it may still be installing"
fi

printf '%s\n' "$lease"
