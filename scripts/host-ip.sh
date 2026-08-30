#!/usr/bin/env bash
# Print the lease address for a host.
#
# The edge images do not run qemu-guest-agent, so `virsh domifaddr` comes back
# empty; the DHCP lease on the cluster network is the reliable source.
#
#   host-ip.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"

# Match the MAC by its shape. The table has a header row, and an earlier
# version took "MAC" from that header as the address.
mac="$(virsh domiflist "$name" |
	awk '$5 ~ /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/ { print $5 }' | head -n1)"
[ -n "$mac" ] || die "no interface found on $name"

net="$(virsh domiflist "$name" |
	awk '$2 == "network" && $5 ~ /^([0-9a-fA-F]{2}:){5}/ { print $3 }' | head -n1)"
[ -n "$net" ] || die "$name is not attached to a libvirt network"

# The lease table also has a header. Take the address only from a row whose
# MAC matches and whose address column looks like an address.
lease="$(virsh net-dhcp-leases "$net" |
	awk -v m="$mac" '$3 == m && $5 ~ /^[0-9]+\./ { print $5 }' |
	cut -d/ -f1 | head -n1)"

if [ -z "$lease" ]; then
	die "no DHCP lease for $name ($mac) on $net yet -- it may still be installing"
fi

printf '%s\n' "$lease"
