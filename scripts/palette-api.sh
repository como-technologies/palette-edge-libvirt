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
#   palette-api.sh profiles
#   palette-api.sh packs edge-k8s

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

action="${1:?give an action: projects, hosts, tokens, clusters, profiles, or packs}"
project="${PALETTE_PROJECT:-}"

need curl
need python3

# Resolve the API key before any pipeline runs. die() inside a pipeline stops
# only the subshell, and the reader then fails on empty input.
need_api_key

# require_project_uid: print the uid of PALETTE_PROJECT, or stop with a clear
# message that names the projects that do exist.
require_project_uid() {
	body="$(project_list)"
	printf '%s' "$body" | PROJECT="$project" python3 -c '
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
	body="$(project_list)"
	printf '%s' "$body" | PROJECT="$project" python3 -c '
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
	body="$(edge_host_list "$uid")"
	printf '%s' "$body" | python3 -c '
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
	body="$(token_list)"
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
	# Everything that Palette knows about the clusters of this project: the
	# uid, the API endpoint, each cluster profile, and the console page.
	#
	# This recipe reads Palette and nothing else, so it answers for a cluster
	# that this checkout did not build. `just cluster-show` reads the
	# OpenTofu state instead, so it knows only the cluster of this project on
	# this workstation, and it says nothing after the state is gone.
	need_project
	uid="$(require_project_uid)"
	info "clusters in project $project"
	body="$(api GET "v1/spectroclusters?limit=100" -H "ProjectUid: $uid")"
	printf '%s' "$body" | PROJECT_UID="$uid" python3 -c '
import json, os, sys

project_uid = os.environ["PROJECT_UID"]

# Palette keeps the record of a cluster that it deleted. That record is not a
# cluster, so it does not belong in this list.
items = [c for c in (json.load(sys.stdin).get("items") or [])
         if ((c.get("status") or {}).get("state") or "") != "Deleted"]
if not items:
    print("  none. To make one: just cluster-up")
    sys.exit(0)

for c in items:
    meta = c.get("metadata") or {}
    status = c.get("status") or {}
    annotations = meta.get("annotations") or {}

    # Not status.health. That field is null on every cluster of this API, so
    # a health column reported "-" for a cluster that was in good order. The
    # conditions carry the state that Palette really holds.
    #
    # No backtick in this block. shellcheck reads one inside a single-quoted
    # string as a command substitution and reports SC2016.
    conditions = status.get("conditions") or []
    true_count = len([x for x in conditions if x.get("status") == "True"])

    print("  {:<20} {:<14} {} of {} condition(s) true".format(
        meta.get("name", "-"), status.get("state", "-"),
        true_count, len(conditions),
    ))
    print("    {:<10} {}".format("uid", meta.get("uid", "-")))

    # The address of the API server. For this lab it is the virtual address
    # that kube-vip claims, which is CLUSTER_VIP.
    for endpoint in status.get("apiEndpoints") or []:
        print("    {:<10} https://{}:{}".format(
            "api", endpoint.get("host", "-"), endpoint.get("port", "-"),
        ))

    # One line for each cluster profile. The type "cluster" is the
    # infrastructure profile, and "add-on" is an add-on profile.
    for profile in (c.get("spec") or {}).get("clusterProfileTemplates") or []:
        print("    {:<10} {:<22} {:<10} {}".format(
            "profile", profile.get("name", "-"),
            profile.get("type", "-"), profile.get("uid", "-"),
        ))

    # A dedicated instance uses a console of its own, and Palette gives its
    # name here. Fall back to the SaaS console.
    root = annotations.get("rootDomain") or "console.spectrocloud.com"
    print("    {:<10} https://{}/projects/{}/clusters/{}/overview".format(
        "console", root, project_uid, meta.get("uid", "-"),
    ))
'
	;;
profiles)
	# The cluster profiles of the project, whatever made them.
	#
	# `cluster-down` removes the profiles that `cluster-up` made, and it finds
	# them in the OpenTofu state. A run that failed between the profile and the
	# state leaves one that no state names, and a project that holds such a
	# profile refuses to be deleted:
	#
	#   Unable to delete the resource as cilab-infra clusterprofile(s) in-use
	#
	# This recipe is how you see that. `just remove-project` deletes them.
	need_project
	uid="$(require_project_uid)"
	info "cluster profiles in project $project"
	body="$(cluster_profile_list "$uid")"
	printf '%s' "$body" | python3 -c '
import json, sys
items = json.load(sys.stdin).get("items") or []
if not items:
    print("  none")
    sys.exit(0)
for profile in items:
    meta = profile["metadata"]
    # The type, the cloud, and the packs are on the PUBLISHED profile, not on
    # the spec. A spec.type does not exist, and a column that reads it prints
    # "-" for every profile. No backtick here: shellcheck reads one inside a
    # single-quoted string as a command substitution and reports SC2016.
    published = (profile.get("spec") or {}).get("published") or {}
    packs = published.get("packs") or []
    print("  {:<24} {:<10} {:<12} {:<26} {} pack(s)".format(
        meta.get("name", "-"),
        published.get("type", "-"),
        published.get("cloudType", "-"),
        meta.get("uid", "-"),
        len(packs),
    ))
'
	;;
packs)
	# The versions of one pack in the public registry. This answers the
	# question that a re-pin asks: which versions does Palette offer now?
	# The cluster layer pins each version in the justfile.
	#
	# The filter names the pack only. An earlier version added
	# ANDspec.cloudTypes=edge-native, and that hid every add-on pack: an
	# add-on such as spectro-k8s-dashboard carries the cloud type "all", so
	# the recipe answered "the registry holds no pack of that name" for a
	# pack that the registry does hold. The cloud type is a column now, and
	# a wrong-cloud pack shows as the wrong word instead of as an absence.
	#
	# With a version, the recipe prints the default values of that one
	# version instead of the list. The repository vendors pack values
	# (terraform/values/) and it replaces one line of others, and both of
	# those need the default values of the pinned version in front of you.
	name="${2:?give a pack name, for example edge-k8s}"
	version="${3:-}"
	body="$(api GET "v1/packs?limit=100" \
		--data-urlencode "filters=spec.name=${name}" -G)"

	if [ -n "$version" ]; then
		info "default values of $name $version"
		printf '%s' "$body" | PACK="$name" VERSION="$version" python3 -c '
import json, os, sys
name, want = os.environ["PACK"], os.environ["VERSION"]
for pack in json.load(sys.stdin).get("items") or []:
    if pack["spec"]["version"] == want:
        sys.stdout.write(pack["spec"].get("values") or "")
        sys.exit(0)
sys.exit(
    "error: the public registry holds no " + name + " " + want + ".\n"
    "       To see the versions it does hold:  just palette-packs " + name
)
'
		exit 0
	fi

	info "versions of the pack $name in the public registry"
	printf '%s' "$body" | python3 -c '
import json, re, sys

def key(version):
    return [int(part) if part.isdigit() else 0
            for part in re.split(r"[._-]", version)]

seen = {}
for pack in json.load(sys.stdin).get("items") or []:
    spec = pack["spec"]
    # Palette holds each pack in two registries. Report the version one time.
    seen[spec["version"]] = (
        spec.get("annotations", {}).get("system_state", "active"),
        spec.get("layer") or "-",
        spec.get("addonType") or ",".join(spec.get("cloudTypes") or []) or "-",
    )
if not seen:
    sys.exit("error: the public registry holds no pack of that name")
print("  {:<16} {:<12} {:<12} {}".format("version", "layer", "cloud/type", "state"))
for version in sorted(seen, key=key):
    state, layer, kind = seen[version]
    print("  {:<16} {:<12} {:<12} {}".format(version, layer, kind, state))
'
	;;
*)
	die "unknown action '$action'. Use projects, hosts, tokens, clusters,
     profiles, or packs."
	;;
esac
