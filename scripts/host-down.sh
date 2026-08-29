#!/usr/bin/env bash
# Stop one edge host VM, remove it, and delete its disk.
#
# This script removes the local VM only. The Edge Host entry stays in Palette.
# Remove that entry in Palette at Clusters > Edge Hosts.
#
# This script is idempotent. It reports a skip if the domain is absent.
#
#   host-down.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"
need virsh

if ! have_domain "$name"; then
	skip "domain $name is absent"
	exit 0
fi

# Read the disk paths before the undefine. The definition is the only record of
# these paths.
mapfile -t disks < <(
	virsh domblklist "$name" --details |
		awk '$1 == "file" && $2 == "disk" { print $4 }'
)

if [ "$(domain_state "$name")" != "shut off" ]; then
	virsh destroy "$name" >/dev/null
fi

# --nvram deletes the UEFI variable store if the domain has one. A domain with
# the standard firmware has none, and older libvirt versions reject the option
# in that case. Try it, then undefine without it.
virsh undefine "$name" --nvram >/dev/null 2>&1 ||
	virsh undefine "$name" >/dev/null

for disk in "${disks[@]}"; do
	[ -f "$disk" ] || continue
	rm -f "$disk" 2>/dev/null || sudo rm -f "$disk"
	info "deleted $disk"
done

info "removed $name"
