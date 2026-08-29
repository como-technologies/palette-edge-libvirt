#!/usr/bin/env bash
# List the VMs of one lab with their state and address.
#
#   lab-ls.sh <lab-prefix>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

lab="${1:?lab prefix required}"
need virsh

mapfile -t domains < <(virsh list --all --name | grep "^${lab}-" || true)

if [ "${#domains[@]}" -eq 0 ]; then
	skip "there are no ${lab}-* domains"
	exit 0
fi

printf '%-16s %-12s %s\n' NAME STATE ADDRESS
for domain in "${domains[@]}"; do
	address="$("$(dirname "${BASH_SOURCE[0]}")/host-ip.sh" "$domain" 2>/dev/null || echo '-')"
	printf '%-16s %-12s %s\n' "$domain" "$(domain_state "$domain")" "$address"
done
