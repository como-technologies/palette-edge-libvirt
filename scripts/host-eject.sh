#!/usr/bin/env bash
# Remove the installer ISO and the seed ISO from a host.
#
# Do this after the installation is complete. The seed ISO holds the
# registration token, so an ejected host keeps no copy of the token.
#
# This script is idempotent. An empty drive stays empty.
#
#   host-eject.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"
need virsh

have_domain "$name" || die "domain $name is absent"

# Find each CD-ROM target that still holds a file.
mapfile -t targets < <(
	virsh domblklist "$name" --details |
		awk '$2 == "cdrom" && $4 != "-" { print $3 }'
)

if [ "${#targets[@]}" -eq 0 ]; then
	skip "$name has no loaded CD-ROM drive"
	exit 0
fi

# Read the file paths before the eject, because the eject removes them from the
# definition.
mapfile -t sources < <(
	virsh domblklist "$name" --details |
		awk '$1 == "file" && $2 == "cdrom" && $4 != "-" { print $4 }'
)

for target in "${targets[@]}"; do
	# --config updates the stored definition. --live also updates a running
	# domain. --live fails on a stopped domain, so try it separately.
	virsh change-media "$name" "$target" --eject --config >/dev/null
	virsh change-media "$name" "$target" --eject --live >/dev/null 2>&1 || true
	info "ejected $target from $name"
done

# The seed ISO holds the registration token. An ejected host keeps no copy, so
# the file in the pool goes as well. seeds/ keeps the original.
for source in "${sources[@]}"; do
	case "$source" in
	*-seed.iso)
		[ -f "$source" ] || continue
		rm -f "$source" 2>/dev/null || sudo rm -f "$source"
		info "deleted $source"
		;;
	esac
done
