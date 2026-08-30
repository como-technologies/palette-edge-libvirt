#!/usr/bin/env bash
# Print the version and the checksum of the current runner release.
#
# The justfile pins both. A pinned checksum is what makes it safe to run the
# runner on your workstation: the download is then the file that GitHub
# published and not a file that something replaced.
#
# This script changes no file. It prints the two lines to put in the justfile.
#
#   runner-pin.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# `gh` is often a shell function in the environment of the person who calls
# this script, and an interactive function is not written for `set -u`. Every
# call below therefore uses `command`, which runs the program and not the
# function.
gh() { command gh "$@"; }


command gh --version >/dev/null 2>&1 || die "the GitHub CLI is not installed."
gh auth status >/dev/null 2>&1 || die "the GitHub CLI holds no credentials. Run: gh auth login"

body="$(gh api repos/actions/runner/releases/latest 2>/dev/null || true)"
[ -n "$body" ] || die "cannot read the releases of actions/runner"

printf '%s' "$body" | python3 -c '
import json, sys
data = json.load(sys.stdin)
tag = (data.get("tag_name") or "").lstrip("v")
for asset in data.get("assets") or []:
    name = asset["name"]
    if name.startswith("actions-runner-linux-x64-") and name.endswith(".tar.gz"):
        digest = (asset.get("digest") or "").split(":")[-1]
        if not digest:
            sys.exit("error: the release gives no checksum for " + name)
        print("==> the current release is " + tag)
        print()
        print("    Put these two lines in the justfile:")
        print()
        print("runner_version := env_var_or_default(\"RUNNER_VERSION\", \"%s\")" % tag)
        print("runner_sha256 := env_var_or_default(\"RUNNER_SHA256\", \"%s\")" % digest)
        break
else:
    sys.exit("error: the release holds no linux-x64 archive")
'
