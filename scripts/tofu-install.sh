#!/usr/bin/env bash
# Install the OpenTofu command for your user and test its checksum.
#
# The cluster layer needs OpenTofu. Ubuntu does not package it, so this script
# takes the release archive from the OpenTofu project and puts the one binary
# in ~/.local/bin. The install needs no root, and `just tofu-uninstall` removes
# it again.
#
# The version is pinned. A pinned version keeps the state file and the provider
# lock file readable by every workstation of the project. Change TOFU_VERSION to
# move it.
#
# This script is idempotent. It reports a skip when the wanted version is
# already in place.
#
# Env: TOFU_VERSION BIN_DIR CACHE_DIR
#
#   TOFU_VERSION=1.12.6 BIN_DIR=~/.local/bin CACHE_DIR=~/.cache/... tofu-install.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

version="${TOFU_VERSION:?tofu version required}"
bin="${BIN_DIR:-$(bin_dir)}"
cache="${CACHE_DIR:-$(cache_dir)/tofu}"

need curl
need unzip

dest="$bin/tofu"

# installed_version: print the version of the binary that this script owns, or
# nothing. `tofu version` prints "OpenTofu v1.12.6" on its first line.
installed_version() {
	[ -x "$dest" ] || return 0
	"$dest" version 2>/dev/null | head -n1 | sed -n 's/^OpenTofu v\([0-9][^ ]*\).*/\1/p'
}

have="$(installed_version)"
if [ "$have" = "$version" ]; then
	skip "$dest is already OpenTofu $version"
	exit 0
fi

# ANCHOR: url
# The OpenTofu project publishes one archive and one checksum file for each
# release. Both names contain the version, so a cache holds every version.
base="https://github.com/opentofu/opentofu/releases/download/v${version}"
archive="tofu_${version}_linux_amd64.zip"
sums="tofu_${version}_SHA256SUMS"
# ANCHOR_END: url

mkdir -p "$cache" "$bin"

info "download OpenTofu $version"
curl -fsSL --retry 3 -o "$cache/$sums" "$base/$sums" ||
	die "cannot read $base/$sums. Check TOFU_VERSION."
curl -fL --retry 3 -o "$cache/${archive}.part" "$base/$archive" ||
	die "cannot read $base/$archive. Check TOFU_VERSION."
mv "$cache/${archive}.part" "$cache/$archive"

want="$(awk -v f="$archive" '$2 == f || $2 == "*" f { print $1 }' "$cache/$sums" | head -n1)"
[ -n "$want" ] || die "$sums names no checksum for $archive"
got="$(sha256sum "$cache/$archive" | cut -d' ' -f1)"
[ "$want" = "$got" ] || die "the downloaded $archive does not match the published checksum"

# Unzip writes to a temporary directory, so a failed extraction leaves no
# partial binary on PATH.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q -o "$cache/$archive" tofu -d "$tmp"
install -m 0755 "$tmp/tofu" "$dest"

got="$(installed_version)"
[ "$got" = "$version" ] || die "$dest reports version '$got' and not $version"

info "installed $(short_path "$dest") (OpenTofu $version), checksum correct"

case ":$PATH:" in
*":$bin:"*) ;;
*)
	warn "$(short_path "$bin") is not on PATH.
         Add it to your shell profile:  export PATH=\"\$HOME/.local/bin:\$PATH\""
	;;
esac
