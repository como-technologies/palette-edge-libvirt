#!/usr/bin/env bash
# Stop and remove the storage pool.
#
# This script keeps the disk image files. `just infra-down` removes the machines
# and their disks, and then removes this pool. It refuses while a domain holds a
# disk here, because the pool is the record of which files belong to the
# tooling.
#
# The script removes the pool directory as well, if the directory is empty.
#
# This script is idempotent.
#
# Give FORCE=1 to remove the pool while a domain still holds a disk in it.
#
# Env: POOL FORCE

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${POOL:?}"
need virsh

if ! virsh pool-info "$POOL" >/dev/null 2>&1; then
	skip "pool $POOL is absent"
	exit 0
fi

# Read the directory before the undefine. The definition is the only record of
# it.
target="$(virsh pool-dumpxml "$POOL" 2>/dev/null |
	sed -n 's:.*<path>\(.*\)</path>.*:\1:p' | head -n1 || true)"

# libvirt removes a pool whose volumes a domain has open, exactly as it removes
# a network in use. The disk file survives, but the record of where it belongs
# does not, and host-down.sh reads the pool to tell its own files from yours.
mapfile -t users < <(domains_using_pool "$target")
if [ "${#users[@]}" -gt 0 ] && [ "${FORCE:-0}" != "1" ]; then
	die "pool $POOL holds a disk of ${#users[@]} domain(s):
       ${users[*]}
     Remove the machines first:  just infra-down
     To remove the pool anyway:  FORCE=1 just pool-down"
fi

# Read the directory again first. libvirt answers vol-list from a cached list,
# and infra-down.sh deletes the files of a domain that is already gone just
# before it calls this script. Without the refresh the warning below names
# volumes that went minutes ago.
virsh pool-refresh "$POOL" >/dev/null 2>&1 || true

volumes="$(virsh vol-list "$POOL" 2>/dev/null | tail -n +3 | grep -c . || true)"
if [ "$volumes" -gt 0 ]; then
	warn "pool $POOL still holds $volumes volume(s). The files stay on disk."
fi

if [ "$(virsh pool-info "$POOL" | awk '/^State:/ { print $2 }')" = "running" ]; then
	virsh pool-destroy "$POOL" >/dev/null
	info "stopped pool $POOL"
fi

virsh pool-undefine "$POOL" >/dev/null
info "removed pool $POOL"

# The pool directory itself.
#
# rmdir needs write permission on the PARENT, and the parent is
# /var/lib/libvirt/images, which belongs to root. So this succeeds only where
# the parent is yours, and it asks for no password.
#
# An empty directory that stays costs nothing, and `just pool-up` uses it again
# with no second password. Report the difference between the two reasons: a
# directory that holds a file holds a disk image, and that is worth saying.
if [ -n "$target" ] && [ -d "$target" ]; then
	if [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
		skip "kept $target, because it still holds a file"
	elif rmdir "$target" 2>/dev/null; then
		info "removed $target"
	else
		skip "kept the empty directory $target, because its parent belongs to root"
	fi
fi
