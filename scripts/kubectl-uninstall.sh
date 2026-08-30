#!/usr/bin/env bash
# Remove the kubectl command that `just kubectl-install` put in ~/.local/bin,
# and the release binaries that it cached.
#
# This script removes only the binary at BIN_DIR/kubectl. A kubectl from your
# package manager sits elsewhere on PATH, and this script does not reach it.
#
# This script is idempotent.
#
# Env: BIN_DIR CACHE_DIR
#
#   kubectl-uninstall.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bin="${BIN_DIR:-$(bin_dir)}"
cache="${CACHE_DIR:-$(cache_dir)/kubectl}"

dest="$bin/kubectl"

if [ -e "$dest" ]; then
	rm -f "$dest"
	info "removed $(short_path "$dest")"
else
	skip "there is no $(short_path "$dest")"
fi

if [ -d "$cache" ]; then
	rm -rf "$cache"
	info "removed the cached release binaries in $(short_path "$cache")"
else
	skip "there are no cached release binaries"
fi
