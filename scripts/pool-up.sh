#!/usr/bin/env bash
# Create and start the storage pool that holds the VM disks.
#
# This script is idempotent. It defines the pool only if the pool is absent.
#
# Env: POOL LAB

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${POOL:?}" "${LAB:?}"
need virsh

target="/var/lib/libvirt/images/$LAB"

if virsh pool-info "$POOL" >/dev/null 2>&1; then
	skip "pool $POOL is already defined"
else
	# libvirt runs as root for the qemu:///system connection. The pool
	# directory needs root to create it.
	sudo mkdir -p "$target"
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
