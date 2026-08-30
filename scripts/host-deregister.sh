#!/usr/bin/env bash
# Remove the Palette record of one host.
#
# `just host-down` removes the virtual machine. The Palette record stays, and
# that record is the one that Palette uses to make a cluster. Two conditions
# need this recipe:
#
#   - You rebuild a host and want a true test. The edge host uid is the host
#     name, so a rebuilt host takes the old record again. The old record then
#     looks like a new registration, and it is not.
#   - You remove a project. `just remove-project` refuses while the project
#     holds a host.
#
# This script is idempotent. It reports a skip if the record is absent.
#
# MACHINES_GO=1 stops the advice about a machine that still runs. `infra-down`
# sets it, because the machine goes a moment later.
#
# Env: MACHINES_GO
#
#   host-deregister.sh <name>

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

name="${1:?name required}"

need curl
need python3
need_api_key
need_project

uid="$(project_uid "$PALETTE_PROJECT")"
[ -n "$uid" ] || die "project $PALETTE_PROJECT does not exist in this tenant.
     To see the names: just palette-projects"

# Read the record by name. The uid of an edge host is its name today, and this
# lookup does not depend on that.
body="$(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid")"
host_uid="$(printf '%s' "$body" |
	NAME="$name" python3 -c '
import json, os, sys
want = os.environ["NAME"]
for host in json.load(sys.stdin).get("items") or []:
    if host["metadata"]["name"] == want:
        print(host["metadata"]["uid"])
        break
')"

if [ -z "$host_uid" ]; then
	skip "$name has no record in project $PALETTE_PROJECT"
	exit 0
fi

api DELETE "v1/edgehosts/$host_uid" -H "ProjectUid: $uid" >/dev/null
info "removed the Palette record of $name"

# The virtual machine keeps its agent and its marker file, so it does not
# register again by itself. Rebuild the host to register it again.
#
# `infra-down` removes the machine a moment later, and sets MACHINES_GO=1 to
# say so. Without that, a teardown printed advice to rebuild a seed for each
# machine that it was deleting.
if [ "${MACHINES_GO:-0}" != "1" ] && have_domain "$name" 2>/dev/null; then
	warn "the domain $name still runs. It does not register again by itself.
         To register it again: just host-down $name, just seed $name,
         then just host-up $name"
fi
