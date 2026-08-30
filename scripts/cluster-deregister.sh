#!/usr/bin/env bash
# Remove the Palette record of every host of this lab.
#
# `just cluster-down` removes the virtual machines. `just nuke` removes the
# virtual machines, the network, the pool, and the seeds. Neither one touches
# your tenant, because a recipe that removes a workstation object must not
# change Palette without a word.
#
# This recipe is the one that changes Palette. Two values give its scope, and
# both come from the environment file of the default project:
#
#   PALETTE_PROJECT   the recipe reads the hosts of this project only
#   LAB_NAME          the recipe keeps the names that start with this prefix
#
# A project holds one lab today, so the prefix normally keeps every host. The
# script names each host that the prefix does not keep, because a silent skip
# leaves a record that nothing removes.
#
# This script is idempotent. A lab with no record gives a skip.
#
# Env: LAB
#
#   cluster-deregister.sh

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

: "${LAB:?}"
here="$(dirname "${BASH_SOURCE[0]}")"

need curl
need python3
need_api_key
need_project

uid="$(project_uid "$PALETTE_PROJECT")"
[ -n "$uid" ] || die "project $PALETTE_PROJECT does not exist in this tenant.
     To see the names: just palette-projects"

# Tag each host, so the script can name the ones that it does not touch.
mapfile -t rows < <(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid" |
	LAB="$LAB" python3 -c '
import json, os, sys
prefix = os.environ["LAB"] + "-"
for host in json.load(sys.stdin).get("items") or []:
    name = host["metadata"]["name"]
    print("lab" if name.startswith(prefix) else "other", name)
')

hosts=()
others=()
for row in "${rows[@]}"; do
	case "$row" in
	"lab "*) hosts+=("${row#lab }") ;;
	"other "*) others+=("${row#other }") ;;
	esac
done

# LAB_NAME gives the prefix. A host that registered under an earlier LAB_NAME
# keeps its old name, and this recipe would leave it with no message.
if [ "${#others[@]}" -gt 0 ]; then
	warn "${#others[@]} host(s) of project $PALETTE_PROJECT do not start with ${LAB}-:
         ${others[*]}
         This recipe left them. To remove one: just host-deregister <host>"
fi

if [ "${#hosts[@]}" -eq 0 ]; then
	skip "no ${LAB}-* host has a record in project $PALETTE_PROJECT"
	exit 0
fi

info "remove ${#hosts[@]} Palette record(s): ${hosts[*]}"
for host in "${hosts[@]}"; do
	"$here/host-deregister.sh" "$host"
done
