#!/usr/bin/env bash
# Shared functions for the Palette API. Source this file. Do not execute it.
#
# The API key goes in a header, never in a URL and never in a message.

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

palette_endpoint() {
	printf '%s\n' "${PALETTE_ENDPOINT:-api.spectrocloud.com}"
}

# need_api_key: put the API key in PALETTE_API_KEY, or stop.
#
# The environment wins, so one command can use a different key. Otherwise the
# key comes from the file that `just api-key-set` writes. The key never lives
# in a project environment file: it is a tenant credential, and a project
# removal must not delete it.
# have_api_key: return 0 when a key is available, from either source.
#
# A test for the key FILE alone is wrong. The environment is a documented way to
# give the key for one command, and it is the only way that continuous
# integration gives it, because a job must leave no credential on the
# workstation. `infra-down.sh` tested the file, so every run with the key in the
# environment skipped the Palette half of the layer without saying so, and left
# a host record for each machine that it deleted.
#
# This makes no message and stops nothing. Use need_api_key where the key is
# necessary.
have_api_key() {
	[ -n "${PALETTE_API_KEY:-}" ] || [ -s "$(api_key_file)" ]
}

need_api_key() {
	if [ -z "${PALETTE_API_KEY:-}" ]; then
		local file
		file="$(api_key_file)"
		if [ -s "$file" ]; then
			PALETTE_API_KEY="$(cat "$file")"
			export PALETTE_API_KEY
		fi
	fi

	if [ -z "${PALETTE_API_KEY:-}" ]; then
		die "there is no Palette API key.
     Store one:   just api-key-set
     Or give one: PALETTE_API_KEY=... just <recipe>
     Palette shows the key at User Menu > My API Keys."
	fi
}

# api METHOD PATH [curl args...]
# Prints the response body on the standard output.
#
# On an HTTP error the script stops and prints the Palette message. That
# message names the cause, for example a token that still uses a project. An
# earlier version sent the body to the caller, and a caller that discarded the
# standard output lost the reason for the failure.
api() {
	local method="$1" path="$2"
	shift 2
	need_api_key

	local response code body
	response="$(curl -sS -w $'\n%{http_code}' -X "$method" \
		-H "ApiKey: $PALETTE_API_KEY" \
		-H "Accept: application/json" \
		"$@" "https://$(palette_endpoint)/$path")" ||
		die "cannot reach https://$(palette_endpoint)/$path"

	code="${response##*$'\n'}"
	body="${response%$'\n'*}"

	if [ "${code:-0}" -ge 400 ]; then
		printf '%s' "$body" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print(raw.strip()[:500], file=sys.stderr)
else:
    message = data.get("message") or raw.strip()[:500]
    print("  Palette says: " + message, file=sys.stderr)
    if data.get("code"):
        print("  Palette code: " + str(data["code"]), file=sys.stderr)
' >&2 || printf '  %s\n' "$body" >&2
		die "$method $path returned HTTP $code"
	fi

	printf '%s' "$body"
}

# token_for_project UID: print the uid of the registration token that names
# this project as its default project. Prints nothing if there is none.
#
# Palette refuses to delete a project while a token still names it.
token_for_project() {
	local body
	body="$(api GET "v1/edgehosts/tokens?limit=100")" || return 1
	printf '%s' "$body" | PEL_UID="$1" python3 -c '
import json, os, sys
want = os.environ["PEL_UID"]
for token in json.load(sys.stdin).get("items") or []:
    project = (token.get("spec") or {}).get("defaultProject") or {}
    if project.get("uid") == want:
        print(token["metadata"]["uid"])
        break
'
}

# token_name UID: print the name of one registration token.
token_name() {
	local body
	body="$(api GET "v1/edgehosts/tokens?limit=100")" || return 1
	printf '%s' "$body" | PEL_UID="$1" python3 -c '
import json, os, sys
want = os.environ["PEL_UID"]
for token in json.load(sys.stdin).get("items") or []:
    if token["metadata"]["uid"] == want:
        print(token["metadata"]["name"])
        break
'
}

# token_value UID: print the registration token itself. Never log this value.
token_value() {
	local body
	body="$(api GET "v1/edgehosts/tokens?limit=100")" || return 1
	printf '%s' "$body" | PEL_UID="$1" python3 -c '
import json, os, sys
want = os.environ["PEL_UID"]
for token in json.load(sys.stdin).get("items") or []:
    if token["metadata"]["uid"] == want:
        print((token.get("spec") or {}).get("token") or "")
        break
'
}

# token_create NAME DESCRIPTION PROJECT_UID DAYS: make a registration token
# that registers hosts into one project. Prints the uid of the new token.
token_create() {
	local body
	body="$(NAME="$1" DESC="$2" PROJECT="$3" DAYS="${4:-90}" python3 -c '
import datetime, json, os
expiry = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(
    days=int(os.environ["DAYS"])
)
print(json.dumps({
    "metadata": {
        "name": os.environ["NAME"],
        "annotations": {"description": os.environ["DESC"]},
    },
    "spec": {
        # The read shape and the write shape differ. A GET returns
        # "defaultProject": {"name": ..., "uid": ...}, but a write takes
        # "defaultProjectUid" as a bare uid. Sending the read shape gives
        # HTTP 204 and no binding at all, and an unbound token registers a
        # host into no project.
        "defaultProjectUid": os.environ["PROJECT"],
        # Palette wants an ISO 8601 time in UTC.
        "expiry": expiry.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
    },
}))
')"
	local created
	created="$(api POST "v1/edgehosts/tokens" \
		-H "Content-Type: application/json" -d "$body")" || return 1
	printf '%s' "$created" |
		python3 -c 'import json,sys; print(json.load(sys.stdin).get("uid",""))'
}

# ANCHOR: clustercount
# cluster_count UID: print the number of clusters that a project still holds.
#
# Palette keeps the record of a cluster that it deleted, with the state
# "Deleted". A count of every item in the list therefore never returns to zero,
# and a recipe that refuses on that count refuses for ever: after a correct
# `just cluster-down`, `just infra-down` reported "the project holds 1
# cluster(s)" and no recipe could make that number smaller. Count the live ones.
cluster_count() {
	local body
	body="$(api GET "v1/spectroclusters?limit=100" -H "ProjectUid: $1")" || return 1
	printf '%s' "$body" | python3 -c '
import json, sys
items = json.load(sys.stdin).get("items") or []
print(len([c for c in items
           if ((c.get("status") or {}).get("state") or "") != "Deleted"]))
'
}
# ANCHOR_END: clustercount

# project_uid NAME
# Prints the uid of the named project, or nothing if the project is absent.
project_uid() {
	local want="$1"
	local body
	body="$(api GET "v1/projects?limit=100")" || return 1
	printf '%s' "$body" | WANT="$want" python3 -c '
import json, os, sys
want = os.environ["WANT"]
for p in json.load(sys.stdin).get("items") or []:
    if p["metadata"]["name"] == want:
        print(p["metadata"]["uid"])
        break
'
}

# project_names
# Prints every project name in the tenant, one for each line.
project_names() {
	local body
	body="$(api GET "v1/projects?limit=100")" || return 1
	printf '%s' "$body" | python3 -c '
import json, sys
for p in json.load(sys.stdin).get("items") or []:
    print(p["metadata"]["name"])
'
}
