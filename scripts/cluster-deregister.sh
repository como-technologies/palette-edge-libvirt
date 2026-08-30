#!/usr/bin/env bash
# Remove the Palette record of every host of this lab.
#
# `just cluster-down` removes the virtual machines. `just nuke` removes the
# virtual machines, the network, the pool, and the seeds. Neither one touches
# your tenant, because a recipe that removes a workstation object must not
# change Palette without a word.
#
# This recipe is the one that changes Palette. It reads the hosts of the
# project, keeps the names that start with the lab prefix, and removes the
# record of each one.
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

# Keep the names of this lab only. One project holds one lab today, and this
# test keeps the recipe correct if that changes.
mapfile -t hosts < <(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid" |
	LAB="$LAB" python3 -c '
import json, os, sys
prefix = os.environ["LAB"] + "-"
for host in json.load(sys.stdin).get("items") or []:
    name = host["metadata"]["name"]
    if name.startswith(prefix):
        print(name)
')

if [ "${#hosts[@]}" -eq 0 ]; then
	skip "no ${LAB}-* host has a record in project $PALETTE_PROJECT"
	exit 0
fi

info "remove ${#hosts[@]} Palette record(s): ${hosts[*]}"
for host in "${hosts[@]}"; do
	"$here/host-deregister.sh" "$host"
done
