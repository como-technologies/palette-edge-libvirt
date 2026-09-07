#!/usr/bin/env bash
# Test each link of the book with mdbook-lint.
#
# mdBook builds a broken link with exit code 0 and no message. Measured against
# mdbook 0.5.4, each of these gives a clean build:
#
#   a link to a heading that does not exist
#   a link to a page that does not exist
#
# The first one occurred four times in one session, each time from a heading
# that took a new number. A reader then arrives at the top of the page.
#
# .mdbook-lint.toml names the rules and says which ones stay off.
#
# The script reports a skip when the tool is absent, in the same way that
# lint-shell.sh does. A person with no cargo can still run `just lint`.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! command -v mdbook-lint >/dev/null 2>&1; then
	skip "mdbook-lint is absent, so the links are not tested."
	skip "  Install it:  cargo install mdbook-lint"
	exit 0
fi

cd "$(repo_root)"

if mdbook-lint lint docs/src/ >/dev/null 2>&1; then
	info "links: each link names a page and a heading that exist"
	exit 0
fi

mdbook-lint lint docs/src/ 2>&1 || true
die "a link of the book does not resolve.
     Each message above names the file, the line, and the correction.
     mdBook builds the book with no message for each of these, so this test is
     the only one that reports them."
