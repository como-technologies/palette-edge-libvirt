#!/usr/bin/env bash
# Test scripts/seed-iso.sh: the one link between the workstation and Palette.
#
# The seed ISO holds the registration token. It also gives the agent the tenant,
# the project, and the name for the registration.
#
# An error in the seed causes a failure that occurs later and gives no message.
# The machine starts. cloud-init reports a success. The host does not show in
# the console.
#
# The script reaches no network, so a real seed is built here, with a token that
# is not one. Nothing outside the temporary directory is touched.

# shellcheck source=tests/assert.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assert.sh"

cd "$(repo_root)"

work="$(tmpdir)"
seeds="$work/seeds"
build="$work/build"

# Values chosen to break a naive template: an apostrophe, a quotation mark, and
# a backslash. YAML 1.2 accepts JSON, so json.dumps is what keeps them valid.
TOKEN='tok"en\with-marks'
PROJECT="O'Brien's Lab"

seed() {
	env PALETTE_PROJECT="$PROJECT" PALETTE_EDGE_TOKEN="$TOKEN" \
		"$@" scripts/seed-iso.sh pe-cp-1 "$seeds" "$build"
}

out="$(seed 2>&1)"
status=$?
is "the seed builds" 0 "$status"

user_data="$build/seed-pe-cp-1/user-data"
rendered="$(cat "$user_data" 2>/dev/null)"

# --- the token is never printed ---------------------------------------------
#
# Rule: never print the token. `just config` and `just preflight` print its
# length only, and the build must not undo that.
hasnt "the build prints no token" "$out" "$TOKEN"

# --- the two classes of value -----------------------------------------------
#
# A scalar is wrapped by json.dumps. A raw value goes in with no quotation
# marks: the boolean must stay a boolean, and the URL already sits inside
# quotation marks in the template. Adding quotes in the template breaks both.

has "an apostrophe in the project name survives" "$rendered" "\"O'Brien's Lab\""
has "a quotation mark in the token is escaped" "$rendered" '\"en'
has "the host name is quoted" "$rendered" '"pe-cp-1"'
has "the endpoint is quoted" "$rendered" '"api.spectrocloud.com"'
has "vip.skip stays a bare boolean" "$rendered" "skip: false"
hasnt "vip.skip is not a quoted string" "$rendered" 'skip: "false"'
has "the agent URL keeps the quotation marks of the template" \
	"$rendered" '"https://github.com/spectrocloud/agent-mode/releases/latest/download/palette-agent-install.sh"'

# stylus.site.name is what makes the libvirt domain name and the Palette host
# name identical, so `just ls` and the Palette host list line up.
has "the site name is the host name" "$rendered" 'name: "pe-cp-1"'

# No placeholder may survive. libvirt and cloud-init both accept a literal
# @NAME@ and then do the wrong thing with it.
hasnt "no placeholder survives the render" "$rendered" "@PALETTE_"
hasnt "no host placeholder survives the render" "$rendered" "@HOSTNAME@"

# --- the modes --------------------------------------------------------------
#
# The rendered user-data holds the token exactly as the ISO does. An earlier
# version protected the ISO only and left a readable copy in the build
# directory.
mode "the seed directory refuses the group and the world" 700 "$seeds"
mode "the build directory refuses the group and the world" 700 "$build"
mode "the rendered user-data is 0600" 600 "$user_data"
if [ -f "$seeds/pe-cp-1-seed.iso" ]; then
	mode "the ISO is 0600" 600 "$seeds/pe-cp-1-seed.iso"
else
	skip "genisoimage and xorriso are both absent, so no ISO was built"
fi

# --- the refusals -----------------------------------------------------------
#
# Each one prevents a machine that boots correctly and registers with nothing.

refuses_with "an empty token is refused" \
	"no host can register" \
	env PALETTE_PROJECT="$PROJECT" PALETTE_EDGE_TOKEN= \
	scripts/seed-iso.sh pe-cp-1 "$seeds" "$build"

refuses_with "no project is refused" \
	"PALETTE_PROJECT is empty" \
	env PALETTE_PROJECT= PALETTE_EDGE_TOKEN="$TOKEN" \
	scripts/seed-iso.sh pe-cp-1 "$seeds" "$build"

# A non-boolean here renders `skip: yes` into the site config, and the agent
# reads a string where it wants a boolean.
refuses_with "a vip.skip that is not a boolean is refused" \
	"must be true or false" \
	env PALETTE_PROJECT="$PROJECT" PALETTE_EDGE_TOKEN="$TOKEN" PALETTE_VIP_SKIP=yes \
	scripts/seed-iso.sh pe-cp-1 "$seeds" "$build"

# --- the settings that change the seed --------------------------------------

seed PALETTE_VIP_SKIP=true >/dev/null 2>&1
has "PALETTE_VIP_SKIP=true reaches the site config" \
	"$(cat "$user_data")" "skip: true"

seed PALETTE_ENDPOINT=api.example.com >/dev/null 2>&1
has "a dedicated endpoint reaches the site config" \
	"$(cat "$user_data")" '"api.example.com"'

seed PALETTE_AGENT_VERSION=v4.7.6 >/dev/null 2>&1
has "a pinned agent version names that release" \
	"$(cat "$user_data")" "download/v4.7.6/palette-agent-install.sh"

# --- the result is valid YAML -----------------------------------------------
#
# The site config is a string inside the outer document, so both halves parse.
# seed-iso.sh makes this test itself when PyYAML is present; this repeats it so
# the tally names it, and skips in the same way when the module is absent.
seed >/dev/null 2>&1
if python3 -c 'import yaml' 2>/dev/null; then
	accepts "the rendered user-data is valid YAML on both levels" \
		python3 -c '
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
site = [f for f in data["write_files"]
        if f["path"].endswith("site-config.yaml")][0]
inner = yaml.safe_load(site["content"])
assert isinstance(inner["stylus"]["vip"]["skip"], bool), "vip.skip is not a boolean"
assert inner["stylus"]["site"]["projectName"] == sys.argv[2], "the project name changed"
assert inner["stylus"]["site"]["edgeHostToken"] == sys.argv[3], "the token changed"
' "$user_data" "$PROJECT" "$TOKEN"
else
	skip "PyYAML is absent, so the YAML of the seed is not parsed"
fi
