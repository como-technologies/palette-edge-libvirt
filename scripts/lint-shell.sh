#!/usr/bin/env bash
# Test all shell scripts with shellcheck.
#
# The script reports a skip if shellcheck is not installed. This keeps `just
# lint` usable on a workstation without the tool.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! command -v shellcheck >/dev/null 2>&1; then
	skip "shellcheck is not installed. Run: sudo apt-get install shellcheck"
	exit 0
fi

cd "$(repo_root)"

# tests/ as well as scripts/. A test file is a shell script too, and a test
# that no linter read is a test that can pass for the wrong reason.
#
# Do not start a comment line in this repository with the word that follows a
# hash and names this tool: it reads that as a directive and fails to parse it.
shellcheck --external-sources scripts/*.sh tests/*.sh
info "shellcheck found no problems"
