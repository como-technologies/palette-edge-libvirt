#!/usr/bin/env bash
# Remove every VM of one lab.
#
# This script keeps the network, the storage pool, and the installer ISO.
# It is idempotent.
#
# Env: LAB POOL

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${LAB:?}"
need virsh
here="$(dirname "${BASH_SOURCE[0]}")"

mapfile -t domains < <(virsh list --all --name | grep "^${LAB}-" || true)

if [ "${#domains[@]}" -eq 0 ]; then
	skip "there are no ${LAB}-* domains"
	exit 0
fi

info "remove ${#domains[@]} domain(s): ${domains[*]}"
for domain in "${domains[@]}"; do
	POOL="${POOL:-}" "$here/host-down.sh" "$domain"
done
