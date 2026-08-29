#!/usr/bin/env bash
# Make .env a regular file again. This is the twin of project-adopt.sh.
#
# The script moves the file that .env points at back to .env. It keeps the
# other environment files.
#
# This script is idempotent. A .env that is already a regular file gives a
# skip.
#
#   project-unadopt.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root="$(repo_root)"
link="$root/.env"

if [ -e "$link" ] && [ ! -L "$link" ]; then
	skip ".env is already a regular file"
	exit 0
fi

[ -L "$link" ] || die ".env is absent. There is nothing to change."

target="$root/$(readlink "$link")"
[ -f "$target" ] || die ".env points at $target, and that file is absent"

rm -f "$link"
mv "$target" "$link"
chmod 600 "$link"

info "moved $(basename "$target") back to .env"
info ".env is a regular file again"
