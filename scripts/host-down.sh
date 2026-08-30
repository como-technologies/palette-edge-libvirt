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

# Read the file paths before the undefine. The definition is the only record of
# them. Take the CD-ROM as well as the disk, because host-up.sh puts a copy of
# the seed ISO in the pool.
mapfile -t files < <(
	virsh domblklist "$name" --details |
		awk '$1 == "file" && ($2 == "disk" || $2 == "cdrom") { print $4 }'
)

if [ "$(domain_state "$name")" != "shut off" ]; then
	virsh destroy "$name" >/dev/null
fi

# --nvram deletes the UEFI variable store if the domain has one. A domain with
# the standard firmware has none, and older libvirt versions reject the option
# in that case. Try it, then undefine without it.
virsh undefine "$name" --nvram >/dev/null 2>&1 ||
	virsh undefine "$name" >/dev/null

# Delete only the files that live in the pool. A file somewhere else belongs to
# you, and this recipe must not remove it.
pool_dir="$(virsh pool-dumpxml "${POOL:-}" 2>/dev/null |
	sed -n 's:.*<path>\(.*\)</path>.*:\1:p' | head -n1)"

for file in "${files[@]}"; do
	[ -f "$file" ] || continue
	if [ -n "$pool_dir" ] && [ "${file#"$pool_dir"/}" = "$file" ]; then
		skip "kept $file, because it is not in the pool"
		continue
	fi
	rm -f "$file" 2>/dev/null || sudo rm -f "$file"
	info "deleted $file"
done

info "removed $name"
