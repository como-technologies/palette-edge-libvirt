#!/usr/bin/env bash
# Read your Palette tenant through the API.
#
# These commands make no change. They answer the two questions that cost the
# most time: does the project name match, and did the host register?
#
# A wrong PALETTE_PROJECT gives no error at installation time. The host
# installs correctly and never shows in the console. `projects` finds that
# condition in one second.
#
#   palette-api.sh projects
#   palette-api.sh hosts

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

action="${1:?give an action: projects or hosts}"
project="${PALETTE_PROJECT:-Default}"

need curl
need python3

# Resolve the API key before any pipeline runs. die() inside a pipeline stops
# only the subshell, and the reader then fails on empty input.
need_api_key

# require_project_uid: print the uid of PALETTE_PROJECT, or stop with a clear
# message that names the projects that do exist.
require_project_uid() {
	api GET "v1/projects?limit=100" | PROJECT="$project" python3 -c '
import json, os, sys
want = os.environ["PROJECT"]
items = json.load(sys.stdin).get("items") or []
names = [p["metadata"]["name"] for p in items]
for p in items:
    if p["metadata"]["name"] == want:
        print(p["metadata"]["uid"])
        sys.exit(0)
have = ", ".join(repr(n) for n in names)
sys.exit(
    "error: PALETTE_PROJECT=" + repr(want) + " does not exist in this tenant.\n"
    "       The tenant has: " + have + "\n"
    "       The name is case sensitive. Correct it in .env."
)
'
}

case "$action" in
projects)
	info "projects in this tenant"
	api GET "v1/projects?limit=100" | PROJECT="$project" python3 -c '
import json, os, sys
want = os.environ["PROJECT"]
items = json.load(sys.stdin).get("items") or []
for p in items:
    name = p["metadata"]["name"]
    uid = p["metadata"]["uid"]
    mark = "  <- PALETTE_PROJECT" if name == want else ""
    print("  {:<24} {}{}".format(name, uid, mark))
if want not in [p["metadata"]["name"] for p in items]:
    sys.exit(
        "\nerror: PALETTE_PROJECT=" + repr(want)
        + " is not in this list. Correct it in .env."
    )
'
	;;
hosts)
	uid="$(require_project_uid)"
	info "registered hosts in project $project"
	api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid" | python3 -c '
import json, sys
items = json.load(sys.stdin).get("items") or []
if not items:
    print("  none yet")
    sys.exit(0)
for h in items:
    meta = h.get("metadata", {})
    status = h.get("status", {}) or {}
    health = (status.get("health") or {}).get("state", "-")
    name = meta.get("name", "-")
    state = status.get("state", "-")
    print("  {:<20} {:<14} health={}".format(name, state, health))
'
	;;
*)
	die "unknown action '$action'. Use projects or hosts."
	;;
esac
