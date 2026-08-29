#!/usr/bin/env bash
# Download the Palette Edge installer ISO into the cache directory.
#
# This script is idempotent. It downloads the file only if the cache does not
# hold it. Each file name contains the version, so two versions can coexist.
#
#   iso-fetch.sh <version> <url-or-empty> <iso-dir>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

version="${1:?version required}"
url="${2:-}"
iso_dir="${3:?iso dir required}"

need curl

# ANCHOR: url
# Spectro Cloud releases the generic installer ISO as a CanvOS release asset.
# Set EDGE_INSTALLER_URL in .env to use a different source, for example the
# download link in your own tenant.
default_url="https://github.com/spectrocloud/CanvOS/releases/download/${version}/palette-edge-installer.iso"
# ANCHOR_END: url

[ -n "$url" ] || url="$default_url"

mkdir -p "$iso_dir"
dest="$iso_dir/palette-edge-installer-${version}.iso"

if [ -s "$dest" ]; then
	skip "the cache already holds $(basename "$dest")"
	exit 0
fi

info "download $url"

# The download writes to a .part file. A failed download leaves no file that
# looks complete to the next run. -C - continues a partial download.
if ! curl -fL --retry 3 -C - -o "${dest}.part" "$url"; then
	die "the download failed. Check EDGE_INSTALLER_VERSION in .env, or set
     EDGE_INSTALLER_URL to the ISO link from your Palette tenant at
     Clusters > Edge Hosts > Add Edge Host."
fi

mv "${dest}.part" "$dest"
info "cached $dest ($(du -h "$dest" | cut -f1))"
