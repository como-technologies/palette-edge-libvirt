#!/usr/bin/env bash
# Create and start the storage pool that holds the VM disks.
#
# This script is idempotent. It defines the pool only if the pool is absent.
#
# Env: POOL CLUSTER

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${POOL:?}" "${CLUSTER:?}"
need virsh

target="$(pool_target "$CLUSTER")"

# A session pool lives in the home directory, so nothing below needs root. The
# session daemon runs as you and writes there without help.
if libvirt_session; then
	mkdir -p "$target"
	skip "session pool directory $target"
else

# --- the part that needs root -----------------------------------------------
#
# libvirt runs as root for the qemu:///system connection, and
# /var/lib/libvirt/images belongs to root. The directory therefore needs root
# one time: to create it, and to give it to you. host-up.sh then copies the
# cloud image without sudo, and host-down.sh deletes the disk without sudo.
# libvirt gives the disk file to the qemu user while a domain runs, and gives it
# back when the domain stops, so this ownership does not disturb it.
#
# All of it happens BEFORE pool-define-as. An earlier version defined the pool
# first, so a failure here left a pool that was defined, inactive, and unusable,
# and the next run reported "already defined" and failed again in the same
# place.
if [ ! -d "$target" ] || [ ! -w "$target" ]; then
	# `just nuke` keeps this directory, so most runs reach neither branch.
	# A run that does needs a password, and a recipe that asks for one fails
	# where there is no terminal. Say so before sudo prints its own message,
	# which names no correction at all.
	if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
		die "the storage pool needs root one time, and this session can
     neither ask for a password nor use a cached one.
     Give sudo the password first, then run the recipe again:
       sudo -v && just pool-up
     Or make the directory yourself:
       sudo mkdir -p $target && sudo chown $USER $target"
	fi

	info "the storage pool directory needs root one time"
	sudo mkdir -p "$target" ||
		die "could not create $target. Run: sudo mkdir -p $target"
	sudo chown "$USER" "$target" ||
		die "could not give $target to $USER. Run: sudo chown $USER $target"
	sudo chmod 0755 "$target"
	info "gave $target to $USER"
fi
fi

if virsh pool-info "$POOL" >/dev/null 2>&1; then
	skip "pool $POOL is already defined"
else
	virsh pool-define-as "$POOL" dir --target "$target" >/dev/null
	info "defined pool $POOL at $target"
fi

# pool-build creates the directory content. It fails if the content exists.
virsh pool-build "$POOL" >/dev/null 2>&1 || true

if [ "$(virsh pool-info "$POOL" | awk '/^State:/ { print $2 }')" = "running" ]; then
	skip "pool $POOL is already running"
else
	virsh pool-start "$POOL" >/dev/null
	info "started pool $POOL"
fi

virsh pool-autostart "$POOL" >/dev/null
virsh pool-info "$POOL"
