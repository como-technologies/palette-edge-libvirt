#!/usr/bin/env bash
# Report the Palette objects that stay after `just nuke`.
#
# `just nuke` removes every lab object on the workstation. It changes no object
# in your tenant, because a recipe that removes a virtual machine must not
# delete a tenant record without a word.
#
# The recipe said nothing about that, so a host that stayed in the console after
# a nuke looked like a fault. This script names what stays and the recipe that
# removes it.
#
# The script never fails. A workstation with no API key still gets the message.
#
# Env: LAB
#
#   nuke-report.sh

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

: "${LAB:?}"

echo
info "the workstation is clear. Palette keeps its own objects."

# Read the tenant only if the workstation can. A missing key or project is not
# a fault here, so print the general message and stop.
if [ -z "${PALETTE_PROJECT:-}" ] ||
	! command -v curl >/dev/null 2>&1 ||
	! command -v python3 >/dev/null 2>&1 ||
	[ ! -s "$(api_key_file)" ]; then
	printf '    To see the hosts that stay registered:  just palette-hosts\n'
	printf '    To remove those records:                just cluster-deregister\n'
	printf '    The cluster and the profile stay in the console.\n'
	exit 0
fi

uid="$(project_uid "$PALETTE_PROJECT" 2>/dev/null || true)"
if [ -z "$uid" ]; then
	printf '    To see the hosts that stay registered:  just palette-hosts\n'
	exit 0
fi

mapfile -t rows < <(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid" 2>/dev/null |
	LAB="$LAB" python3 -c '
import json, os, sys
prefix = os.environ["LAB"] + "-"
try:
    items = json.load(sys.stdin).get("items") or []
except Exception:
    sys.exit(0)
for host in items:
    name = host["metadata"]["name"]
    print("lab" if name.startswith(prefix) else "other", name)
' 2>/dev/null || true)

hosts=()
others=()
for row in "${rows[@]}"; do
	case "$row" in
	"lab "*) hosts+=("${row#lab }") ;;
	"other "*) others+=("${row#other }") ;;
	esac
done

if [ "${#hosts[@]}" -eq 0 ] && [ "${#others[@]}" -eq 0 ]; then
	printf '    No host has a record in project %s.\n' "$PALETTE_PROJECT"
	exit 0
fi

if [ "${#hosts[@]}" -gt 0 ]; then
	printf '    %s host(s) stay registered in project %s:\n' "${#hosts[@]}" "$PALETTE_PROJECT"
	for host in "${hosts[@]}"; do
		printf '      %s\n' "$host"
	done
	printf '    To remove those records:  just cluster-deregister\n'
fi

# A host of an earlier LAB_NAME. cluster-deregister keeps the prefix, so name
# these separately and give the recipe that removes one.
if [ "${#others[@]}" -gt 0 ]; then
	printf '    %s host(s) of project %s do not start with %s-:\n' \
		"${#others[@]}" "$PALETTE_PROJECT" "$LAB"
	for host in "${others[@]}"; do
		printf '      %s\n' "$host"
	done
	printf '    cluster-deregister leaves those. To remove one: just host-deregister <host>\n'
fi

printf '    Delete the cluster and the profile in the console.\n'
