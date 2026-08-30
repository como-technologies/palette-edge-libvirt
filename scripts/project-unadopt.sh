#!/usr/bin/env bash
# Make .env a regular file in the checkout again.
#
# This is the twin of project-adopt.sh. The script moves the environment file
# of the default project back to .env in the checkout. It keeps the other
# environment files.
#
# This script is idempotent. A .env that is already a regular file gives a
# skip.
#
#   project-unadopt.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pointer="$(env_pointer)"
link="$(env_link)"

if [ -e "$pointer" ] && [ ! -L "$pointer" ]; then
	skip ".env is already a regular file"
	exit 0
fi

[ -L "$pointer" ] || die ".env is absent. There is nothing to change."

# Read the file that the two links reach. `readlink -f` follows the whole
# chain, so it answers for a pointer that names the link and for an old
# pointer that names the file directly.
target="$(readlink -f "$pointer" || true)"
if [ -z "$target" ] || [ ! -f "$target" ]; then
	die ".env points at no file. Choose a project: just default-project <name>"
fi

rm -f "$pointer"
mv "$target" "$pointer"
chmod 600 "$pointer"

# The link named the file that moved. Remove it, or it points at nothing.
if [ -L "$link" ] && [ ! -e "$link" ]; then
	rm -f "$link"
fi

info "moved $(basename "$target") back to .env"
info ".env is a regular file in the checkout again"
warn "the file holds the registration token, and the checkout is a working
         copy. To put it back: just adopt-project <name>"
