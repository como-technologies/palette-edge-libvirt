#!/usr/bin/env bash
# Test scripts/palette-lib.sh: the readers that turn a Palette answer into a
# value that a recipe acts on.
#
# No request leaves this machine. Each test replaces `api` with a function that
# prints a recorded answer, which is the shape that the tenant really returns.
# So these tests cover the part that Palette does not: what the repository does
# with the answer.

# shellcheck source=tests/assert.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assert.sh"
# shellcheck source=scripts/palette-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/palette-lib.sh"
set +e

# stub_api BODY: answer every api call with this body, and record the call.
#
# The recorded call is a test of its own. `edge_host_list` and `project_list`
# are POSTs because Palette stopped answering a GET on those paths in 2026-09,
# and a reader that goes back to a GET returns HTTP 405 with no local symptom.
# The log is a FILE, not a variable. A reader runs `api` inside a command
# substitution, and that is a subshell: a variable it sets is gone before the
# assertion reads it, so every call looked like no call at all.
PEL_LOG="$(tmpdir)/calls"
PEL_BODY=""
api() {
	printf '%s %s\n' "$1" "$2" >>"$PEL_LOG"
	printf '%s' "$PEL_BODY"
}
stub_api() {
	PEL_BODY="$1"
	: >"$PEL_LOG"
}

# last_call: print the method and the path of the most recent request.
last_call() {
	tail -n1 "$PEL_LOG" 2>/dev/null
}

# --- the API key ------------------------------------------------------------
#
# `infra-down` tested the key FILE, so a key given in the environment -- the
# documented way, and the only way CI gives one -- skipped the Palette half of
# the layer with no message and orphaned a host record for every machine.

accepts "a key in the environment is a key" \
	env PALETTE_API_KEY=k HOME="$(tmpdir)" \
	bash -c 'source scripts/palette-lib.sh; have_api_key'
refuses "no key in the environment and no file is no key" \
	env -u PALETTE_API_KEY XDG_CONFIG_HOME="$(tmpdir)" \
	bash -c 'source scripts/palette-lib.sh; have_api_key'
refuses_with "need_api_key names the recipe that stores one" \
	"just api-key-set" \
	env -u PALETTE_API_KEY XDG_CONFIG_HOME="$(tmpdir)" \
	bash -c 'source scripts/palette-lib.sh; need_api_key'

keydir="$(tmpdir)/palette-edge-libvirt"
mkdir -p "$keydir"
printf 'from-the-file' >"$keydir/api-key"
accepts "a key in the file is a key" \
	env -u PALETTE_API_KEY XDG_CONFIG_HOME="$(dirname "$keydir")" \
	bash -c 'source scripts/palette-lib.sh; have_api_key'

# --- cluster_count ----------------------------------------------------------
#
# Palette keeps the record of a cluster that it deleted, with the state
# "Deleted", for ever. A count of every item therefore never returns to zero:
# after a correct `cluster-down`, `infra-down` reported "the project holds 1
# cluster(s)" and no recipe could make that number smaller.

stub_api '{"items":[
  {"metadata":{"name":"old","uid":"u1"},"status":{"state":"Deleted"}},
  {"metadata":{"name":"gone","uid":"u2"},"status":{"state":"Deleted"}},
  {"metadata":{"name":"live","uid":"u3"},"status":{"state":"Running"}},
  {"metadata":{"name":"going","uid":"u4"},"status":{"state":"Deleting"}}
]}'
is "cluster_count counts neither of the two deleted clusters" 2 "$(cluster_count uid)"

stub_api '{"items":[{"metadata":{"name":"old"},"status":{"state":"Deleted"}}]}'
is "a project of deleted clusters only counts zero" 0 "$(cluster_count uid)"

# A cluster that is deleting still holds its cluster profiles, so `cluster-down`
# waits for this number to reach zero. It has to count one.
stub_api '{"items":[{"metadata":{"name":"going"},"status":{"state":"Deleting"}}]}'
is "a cluster that is deleting still counts" 1 "$(cluster_count uid)"

stub_api '{"items":[]}'
is "an empty project counts zero" 0 "$(cluster_count uid)"
stub_api '{}'
is "an answer with no items counts zero" 0 "$(cluster_count uid)"

# --- the projects -----------------------------------------------------------

stub_api '{"items":[
  {"metadata":{"name":"iris","uid":"p1"}},
  {"metadata":{"name":"thelio-lab","uid":"p2"}}
]}'
is "project_uid finds the project" p2 "$(project_uid thelio-lab)"
is "project_uid says nothing about a project that is absent" "" "$(project_uid nope)"
is "project_uid is case sensitive, as Palette is" "" "$(project_uid Iris)"
is "project_names lists every project" "iris thelio-lab" "$(project_names | tr '\n' ' ' | sed 's/ $//')"

project_list >/dev/null
is "project_list is a POST to the dashboard path" \
	"POST v1/dashboard/projects?limit=100" "$(last_call)"

edge_host_list uid >/dev/null
is "edge_host_list is a POST to the search path" \
	"POST v1/dashboard/edgehosts/search?limit=50" "$(last_call)"

# Over 50 this endpoint answers {"code":608}. The limit is not a preference.
has "edge_host_list asks for 50 hosts at most" "$(last_call)" "limit=50"

cluster_profile_list uid >/dev/null
is "cluster_profile_list is still a GET" "GET v1/clusterprofiles?limit=50" "$(last_call)"

# --- the registration tokens ------------------------------------------------
#
# One function holds this endpoint now. Three readers called it separately, and
# four separate calls to `v1/projects` are what made the 2026-09 change cost a
# day instead of a line.

stub_api '{"items":[
  {"metadata":{"name":"iris","uid":"t1"},
   "spec":{"defaultProject":{"name":"iris","uid":"p1"},"token":"secret-one"}},
  {"metadata":{"name":"loose","uid":"t2"},"spec":{"token":"secret-two"}}
]}'
is "token_for_project finds the token bound to the project" t1 "$(token_for_project p1)"
is "token_for_project says nothing when no token names the project" \
	"" "$(token_for_project p9)"
is "an unbound token belongs to no project" "" "$(token_for_project null)"
is "token_name reads the name" iris "$(token_name t1)"
is "token_value reads the token" secret-one "$(token_value t1)"
is "token_value says nothing about a token that is absent" "" "$(token_value t9)"

token_list >/dev/null
is "token_list holds the one token endpoint" \
	"GET v1/edgehosts/tokens?limit=100" "$(last_call)"

# Every token reader goes through that one function. This is the test that
# fails when a second copy of the endpoint appears.
for reader in token_for_project token_name token_value; do
	: >"$PEL_LOG"
	"$reader" t1 >/dev/null
	is "$reader calls token_list and no endpoint of its own" \
		"GET v1/edgehosts/tokens?limit=100" "$(last_call)"
done

# --- the endpoint -----------------------------------------------------------

is "the endpoint defaults to the SaaS API" \
	api.spectrocloud.com "$(unset PALETTE_ENDPOINT; palette_endpoint)"
is "a dedicated instance sets its own endpoint" \
	api.example.com "$(PALETTE_ENDPOINT=api.example.com palette_endpoint)"
