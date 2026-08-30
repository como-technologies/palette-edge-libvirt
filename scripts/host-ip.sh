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
need virsh

# Test the domain first. Without this, virsh prints "failed to get domain" and
# names no correction, and the awk below reads an empty table.
have_domain "$name" || die "domain $name is absent.
     To see the domains of this cluster:  just ls
     To make the machines:                just infra-up"

# Match the MAC by its shape. The table has a header row, and an earlier
# version took "MAC" from that header as the address.
mac="$(virsh domiflist "$name" |
	awk '$5 ~ /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/ { print $5 }' | head -n1)"
[ -n "$mac" ] || die "no interface found on $name"

net="$(virsh domiflist "$name" |
	awk '$2 == "network" && $5 ~ /^([0-9a-fA-F]{2}:){5}/ { print $3 }' | head -n1)"
[ -n "$net" ] || die "$name is not attached to a libvirt network"

# The network can be absent while the domain still names it. `just net-down`
# removes a network and leaves each domain with the reference, and the lease
# table of a network that is gone is not a lease that is late.
virsh net-info "$net" >/dev/null 2>&1 || die "$name is attached to network $net, and that network is absent.
     The machine therefore reaches nothing and never registers.
     Build the machines again:  just infra-down && just infra-up"

# The lease table also has a header. Take the address only from a row whose
# MAC matches and whose address column looks like an address.
#
# `|| true`, so that an empty table reaches the test below. With
# `set -o pipefail` a failure of net-dhcp-leases would stop the script here with
# no message.
lease="$(virsh net-dhcp-leases "$net" 2>/dev/null |
	awk -v m="$mac" '$3 == m && $5 ~ /^[0-9]+\./ { print $5 }' |
	cut -d/ -f1 | head -n1 || true)"

if [ -z "$lease" ]; then
	die "no DHCP lease for $name ($mac) on $net yet -- it may still be installing.
     To watch the boot:  just console $name"
fi

printf '%s\n' "$lease"
