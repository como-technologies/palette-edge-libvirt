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
#   palette-api.sh clusters
#   palette-api.sh packs edge-k8s

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

action="${1:?give an action: projects, hosts, tokens, clusters, or packs}"
project="${PALETTE_PROJECT:-}"

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
    "       The name is case sensitive. Correct PALETTE_PROJECT."
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
if not want:
    print("\n  PALETTE_PROJECT is not set. Select one: just default-project <name>")
elif want not in [p["metadata"]["name"] for p in items]:
    sys.exit(
        "\nerror: PALETTE_PROJECT=" + repr(want)
        + " is not in this list. Correct PALETTE_PROJECT."
    )
'
	;;
hosts)
	need_project
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
tokens)
	info "registration tokens in this tenant"
	body="$(api GET "v1/edgehosts/tokens?limit=100")"
	printf '%s' "$body" | python3 -c '
import json, sys
items = json.load(sys.stdin).get("items") or []
if not items:
    print("  none")
    sys.exit(0)
for token in items:
    project = (token.get("spec") or {}).get("defaultProject") or {}
    name = token["metadata"]["name"]
    bound = project.get("name") or "NO PROJECT -- hosts will not register"
    print("  {:<24} -> {}".format(name, bound))
'
	;;
clusters)
	need_project
	uid="$(require_project_uid)"
	info "clusters in project $project"
	api GET "v1/spectroclusters?limit=100" -H "ProjectUid: $uid" | python3 -c '
import json, sys
# Palette keeps the record of a cluster that it deleted. That record is not a
# cluster, so it does not belong in this list.
items = [c for c in (json.load(sys.stdin).get("items") or [])
         if ((c.get("status") or {}).get("state") or "") != "Deleted"]
if not items:
    print("  none. To make one: just cluster-up")
    sys.exit(0)
for c in items:
    status = c.get("status") or {}
    print("  {:<20} {:<14} health={}".format(
        c["metadata"]["name"],
        status.get("state", "-"),
        (status.get("health") or {}).get("state", "-"),
    ))
'
	;;
packs)
	# The versions of one pack in the public registry. This answers the
	# question that a re-pin asks: which versions does Palette offer now?
	# The cluster layer pins each version in the justfile.
	name="${2:?give a pack name, for example edge-k8s}"
	info "versions of the Edge Native pack $name in the public registry"
	api GET "v1/packs?limit=100" \
		--data-urlencode "filters=spec.name=${name}ANDspec.cloudTypes=edge-native" -G |
		python3 -c '
import json, re, sys

def key(version):
    return [int(part) if part.isdigit() else 0
            for part in re.split(r"[._-]", version)]

seen = {}
for pack in json.load(sys.stdin).get("items") or []:
    spec = pack["spec"]
    # Palette holds each pack in two registries. Report the version one time.
    seen[spec["version"]] = spec.get("annotations", {}).get("system_state", "active")
if not seen:
    sys.exit("error: the public registry holds no Edge Native pack of that name")
for version in sorted(seen, key=key):
    print("  {:<16} {}".format(version, seen[version]))
'
	;;
*)
	die "unknown action '$action'. Use projects, hosts, tokens, clusters, or packs."
	;;
esac
