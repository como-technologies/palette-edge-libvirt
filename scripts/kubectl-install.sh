#!/usr/bin/env bash
# Install the kubectl command for your user and test its checksum.
#
# `just cluster-verify` needs kubectl to read the cluster that the cluster layer
# made. This script takes the binary from the Kubernetes release site and puts
# it in ~/.local/bin. The install needs no root, and `just kubectl-uninstall`
# removes it again.
#
# The version follows K8S_VERSION, because kubectl supports one minor version
# each side of the server. A version of "latest" takes the current stable
# release instead.
#
# This script is idempotent. It reports a skip when the wanted version is
# already in place.
#
# Env: KUBECTL_VERSION BIN_DIR CACHE_DIR
#
#   KUBECTL_VERSION=1.33.13 BIN_DIR=~/.local/bin kubectl-install.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

version="${KUBECTL_VERSION:?kubectl version required}"
bin="${BIN_DIR:-$(bin_dir)}"
cache="${CACHE_DIR:-$(cache_dir)/kubectl}"

need curl

dest="$bin/kubectl"

# The release site names every file with a leading v. K8S_VERSION does not carry
# one, so add it here and accept both shapes.
case "$version" in
latest)
	version="$(curl -fsSL https://dl.k8s.io/release/stable.txt || true)"
	[ -n "$version" ] || die "cannot read the current stable kubectl version.
     Give one instead:  KUBECTL_VERSION=1.33.13 just kubectl-install"
	;;
v*) ;;
*) version="v$version" ;;
esac

# installed_version: print the version of the binary that this script owns, or
# nothing. `kubectl version --client` prints "Client Version: v1.33.13".
installed_version() {
	[ -x "$dest" ] || return 0
	"$dest" version --client 2>/dev/null |
		sed -n 's/^Client Version: \(v[0-9][^ ]*\).*/\1/p' | head -n1
}

have="$(installed_version)"
if [ "$have" = "$version" ]; then
	skip "$dest is already kubectl $version"
	exit 0
fi

# ANCHOR: url
# The Kubernetes project publishes one binary and one checksum file for each
# release. Both paths carry the version, so a cache holds every version.
base="https://dl.k8s.io/release/${version}/bin/linux/amd64"
# ANCHOR_END: url

mkdir -p "$cache" "$bin"

info "download kubectl $version"
curl -fsSL --retry 3 -o "$cache/kubectl-${version}.sha256" "$base/kubectl.sha256" ||
	die "cannot read $base/kubectl.sha256. Check KUBECTL_VERSION."
curl -fL --retry 3 -o "$cache/kubectl-${version}.part" "$base/kubectl" ||
	die "cannot read $base/kubectl. Check KUBECTL_VERSION."
mv "$cache/kubectl-${version}.part" "$cache/kubectl-${version}"

want="$(tr -d ' \n' <"$cache/kubectl-${version}.sha256")"
[ -n "$want" ] || die "the release site gave no checksum for kubectl $version"
got="$(sha256sum "$cache/kubectl-${version}" | cut -d' ' -f1)"
[ "$want" = "$got" ] || die "the downloaded kubectl does not match the published checksum"

install -m 0755 "$cache/kubectl-${version}" "$dest"

got="$(installed_version)"
[ "$got" = "$version" ] || die "$dest reports version '$got' and not $version"

info "installed $(short_path "$dest") (kubectl $version), checksum correct"

case ":$PATH:" in
*":$bin:"*) ;;
*)
	warn "$(short_path "$bin") is not on PATH.
         Add it to your shell profile:  export PATH=\"\$HOME/.local/bin:\$PATH\""
	;;
esac
