#!/usr/bin/env bash
# Show the configuration that the recipes use now.
#
# The justfile exports these values from .env or from its own defaults. This
# script reads the environment, so it always shows the effective value.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

row() { printf '  %-22s %s\n' "$1" "$2"; }

lab="${LAB_NAME:-pe}"

info "lab"
row "LAB_NAME" "$lab"
row "network" "${lab}-net (${LAB_SUBNET:-192.168.140}.0/24)"
row "pool" "${lab}-pool"
row "LIBVIRT_DEFAULT_URI" "${LIBVIRT_DEFAULT_URI:-qemu:///system}"

info "palette"
row "PALETTE_ENDPOINT" "${PALETTE_ENDPOINT:-api.spectrocloud.com}"
row "PALETTE_PROJECT" "${PALETTE_PROJECT:-MISSING. Run: just palette-projects}"
# Never print the token. Print only its status.
if [ -n "${PALETTE_EDGE_TOKEN:-}" ]; then
	row "PALETTE_EDGE_TOKEN" "set (${#PALETTE_EDGE_TOKEN} characters)"
else
	row "PALETTE_EDGE_TOKEN" "MISSING. Run: just new-project <name>"
fi
row "PALETTE_VIP_SKIP" "${PALETTE_VIP_SKIP:-true}"

info "host image"
row "UBUNTU_RELEASE" "${UBUNTU_RELEASE:-noble}"
row "UBUNTU_IMAGE_URL" "${UBUNTU_IMAGE_URL:-(derived from the release)}"

info "topology"
row "control nodes" "${CONTROL_COUNT:-1} x ${CONTROL_VCPUS:-4} vcpu / ${CONTROL_MEMORY_MB:-8192} MB / ${CONTROL_DISK_GB:-60} GB"
row "worker nodes" "${WORKER_COUNT:-2} x ${WORKER_VCPUS:-6} vcpu / ${WORKER_MEMORY_MB:-16384} MB / ${WORKER_DISK_GB:-100} GB"

info "directories"
row "projects" "$(short_path "$(envs_dir)")"
row "API key" "$(short_path "$(api_key_file)")"
row "seeds" "$(short_path "$(data_dir)/seeds")"
row "build" "$(short_path "$(data_dir)/build")"
row "cloud image" "$(short_path "$(cache_dir)/images")"

# The checkout holds one lab file: the .env link. Report what it reaches, and
# name the correction when it reaches nothing.
pointer="$(env_pointer)"
if [ -L "$pointer" ]; then
	if [ -f "$pointer" ]; then
		info "source: $(short_path "$(readlink -f "$pointer")") and the justfile defaults"
	else
		info "source: the justfile defaults only"
		warn ".env points at no file. Choose a project: just default-project <name>"
	fi
elif [ -f "$pointer" ]; then
	info "source: the .env file in the checkout and the justfile defaults"
else
	info "source: the justfile defaults only"
	warn "this checkout reads no project. To see the projects: just projects"
fi
