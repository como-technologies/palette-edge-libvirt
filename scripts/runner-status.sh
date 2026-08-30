#!/usr/bin/env bash
# Show the state of the runner: the service here, and the record in GitHub.
#
# The two can disagree. A runner whose files went without `just runner-down`
# keeps its record in GitHub and shows as offline, and the name is then taken.
#
# The script makes no change.
#
#   runner-status.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# `gh` is often a shell function in the environment of the person who calls
# this script, and an interactive function is not written for `set -u`. Every
# call below therefore uses `command`, which runs the program and not the
# function.
gh() { command gh "$@"; }


info "the service on this workstation"
if systemctl list-units --all --type=service --no-legend 2>/dev/null |
	grep 'actions\.runner\.' | awk '{ printf "  %-52s %s\n", $1, $4 }' | grep .; then
	:
else
	skip "no runner service is installed. To make one: just runner-up"
fi

printf '\n'
info "the record in GitHub"
if ! command gh --version >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
	skip "the GitHub CLI holds no credentials, so this half is unknown"
	exit 0
fi

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$repo" ] || {
	skip "cannot read the repository name"
	exit 0
}

body="$(gh api "repos/$repo/actions/runners" 2>/dev/null || true)"
[ -n "$body" ] || {
	skip "cannot read the runners of $repo. The account needs administration rights."
	exit 0
}

printf '%s' "$body" | python3 -c '
import json, sys
data = json.load(sys.stdin)
runners = data.get("runners") or []
if not runners:
    print("    no runner is registered. To make one: just runner-up")
for r in runners:
    labels = ",".join(l["name"] for l in r.get("labels") or [])
    print("  %-24s %-10s %s" % (r["name"], r["status"], labels))
'
