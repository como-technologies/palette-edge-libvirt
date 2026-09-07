#!/usr/bin/env bash
# Build the book and serve it with live reload.
#
# The script tests the port before it starts mdBook. mdBook prints two lines
# that report a success, and then it stops:
#
#   INFO Serving on: http://localhost:3000
#   INFO Watching for changes...
#   ERROR Unable to serve: panicked at .../serve.rs:137:29:
#   Unable to bind to 127.0.0.1:3000: Address already in use (os error 98)
#
# A person reads the first two lines, opens the browser, and gets the page from
# the OTHER mdBook that holds the port. That one serves an older build and
# reloads nothing. The report is "live reload fails", and the cause is a second
# server.
#
# scripts/dashboard.sh guards the same condition for the same reason.
#
# Env: DOCS_PORT
#
#   docs-serve.sh
#   DOCS_PORT=3001 docs-serve.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${DOCS_PORT:-3000}"

command -v mdbook >/dev/null 2>&1 ||
	die "mdbook is not installed.
     Install it:  cargo install mdbook mdbook-mermaid mdbook-gruvbox"

if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
	exec 3<&-
	die "something already answers on port $port of this workstation.
     It is usually an mdBook from an earlier run. Find it:
       pgrep -af 'mdbook serve'
     Use that one, stop it, or take a different port:
       DOCS_PORT=3001 just docs-serve"
fi

cd "$(repo_root)"
exec mdbook serve docs --port "$port" --open
