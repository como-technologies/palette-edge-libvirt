#!/usr/bin/env bash
# Download the stock Ubuntu cloud image and test its checksum.
#
# The tooling uses the unmodified image from Canonical. It builds no custom
# operating system image. The Palette agent installs at the first boot. See
# docs/src/architecture.md.
#
# This script is idempotent. It downloads the image only if the cache does not
# hold a correct copy. Each file name contains the release.
#
#   image-fetch.sh <release> <url-or-empty> <image-dir>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

release="${1:?release required}"
url="${2:-}"
image_dir="${3:?image dir required}"

need curl

# ANCHOR: url
# Canonical publishes the current cloud image for each release at this path.
# The image is the same one that public clouds use.
base="https://cloud-images.ubuntu.com/${release}/current"
file="${release}-server-cloudimg-amd64.img"
# ANCHOR_END: url

[ -n "$url" ] || url="$base/$file"

mkdir -p "$image_dir"
dest="$image_dir/$file"
sums="$image_dir/SHA256SUMS-$release"

# verify: test the image against the published checksum.
verify() {
	[ -s "$dest" ] || return 1
	[ -s "$sums" ] || return 1
	local want
	want="$(awk -v f="$file" '$2 == "*" f || $2 == f { print $1 }' "$sums" | head -n1)"
	[ -n "$want" ] || return 1
	local got
	got="$(sha256sum "$dest" | cut -d' ' -f1)"
	[ "$want" = "$got" ]
}

# Always take a new checksum file. Canonical rebuilds the current image, so a
# cached checksum can describe a different image.
curl -fsSL --retry 3 -o "$sums" "$base/SHA256SUMS" ||
	die "cannot read $base/SHA256SUMS. Check UBUNTU_RELEASE."

if verify; then
	skip "the cache already holds a correct $file"
	exit 0
fi

if [ -s "$dest" ]; then
	warn "the cached image does not match the checksum. Downloading it again."
	rm -f "$dest"
fi

info "download $url"

# The download writes to a .part file. A failed download leaves no file that
# looks complete to the next run.
if ! curl -fL --retry 3 -C - -o "${dest}.part" "$url"; then
	die "the download failed. Check UBUNTU_RELEASE, or set
     UBUNTU_IMAGE_URL to a direct link."
fi
mv "${dest}.part" "$dest"

verify || die "the downloaded image does not match the published checksum"

info "cached $dest ($(du -h "$dest" | cut -f1)), checksum correct"
