#!/usr/bin/env bash
# Stop and remove the storage pool.
#
# This script keeps the disk image files. Run `just cluster-down` first to
# delete the VM disks. This script is idempotent.
#
# Env: POOL

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${POOL:?}"
need virsh

if ! virsh pool-info "$POOL" >/dev/null 2>&1; then
	skip "pool $POOL is absent"
	exit 0
fi

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
