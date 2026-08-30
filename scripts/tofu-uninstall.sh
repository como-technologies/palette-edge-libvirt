#!/usr/bin/env bash
# Remove the OpenTofu command that `just tofu-install` put in ~/.local/bin, and
# the release archives that it cached.
#
# This script removes only the binary at BIN_DIR/tofu. An OpenTofu from your
# package manager sits elsewhere on PATH, and this script does not reach it.
#
# The state files stay. They name the objects that OpenTofu made in Palette, so
# `just cluster-down` must remove those first. See scripts/cluster-down.sh.
#
# This script is idempotent.
#
# Env: BIN_DIR CACHE_DIR
#
#   tofu-uninstall.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bin="${BIN_DIR:-$(bin_dir)}"
cache="${CACHE_DIR:-$(cache_dir)/tofu}"

dest="$bin/tofu"

if [ -e "$dest" ]; then
	rm -f "$dest"
	info "removed $(short_path "$dest")"
else
	skip "there is no $(short_path "$dest")"
fi

if [ -d "$cache" ]; then
	rm -rf "$cache"
	info "removed the cached release archives in $(short_path "$cache")"
else
	skip "there are no cached release archives"
fi
