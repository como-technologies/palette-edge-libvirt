#!/usr/bin/env bash
# Shared functions for the Palette API. Source this file. Do not execute it.
#
# The API key goes in a header, never in a URL and never in a message.

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

palette_endpoint() {
	printf '%s\n' "${PALETTE_ENDPOINT:-api.spectrocloud.com}"
}

need_api_key() {
	if [ -z "${PALETTE_API_KEY:-}" ]; then
		die "PALETTE_API_KEY is empty.
     Add it to .env, or give it for one command:
       PALETTE_API_KEY=... just <recipe>
     Palette shows the key at User Menu > My API Keys."
	fi
}

# api METHOD PATH [curl args...]
# Prints the response body. Stops the script on an HTTP error and shows the
# body, because the Palette error message names the cause.
api() {
	local method="$1" path="$2"
	shift 2
	need_api_key
	curl -sS --fail-with-body -X "$method" \
		-H "ApiKey: $PALETTE_API_KEY" \
		-H "Accept: application/json" \
		"$@" "https://$(palette_endpoint)/$path"
}

# project_uid NAME
# Prints the uid of the named project, or nothing if the project is absent.
project_uid() {
	local want="$1"
	api GET "v1/projects?limit=100" | WANT="$want" python3 -c '
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
	api GET "v1/projects?limit=100" | python3 -c '
import json, sys
for p in json.load(sys.stdin).get("items") or []:
    print(p["metadata"]["name"])
'
}
