#!/usr/bin/env bash
# Show the configuration that the recipes use now.
#
# The justfile takes these values from the project file or from its own
# defaults. This
# script reads the environment, so it always shows the effective value.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

row() { printf '  %-22s %s\n' "$1" "$2"; }

cluster="${CLUSTER_NAME:-pe}"

info "cluster"
row "CLUSTER_NAME" "$cluster"
row "network" "${cluster}-net (${CLUSTER_SUBNET:-192.168.140}.0/24)"
row "pool" "${cluster}-pool"
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
row "PALETTE_VIP_SKIP" "${PALETTE_VIP_SKIP:-false}"

info "host image"
row "UBUNTU_RELEASE" "${UBUNTU_RELEASE:-noble}"
row "UBUNTU_IMAGE_URL" "${UBUNTU_IMAGE_URL:-(derived from the release)}"

info "topology"
row "control nodes" "${CONTROL_COUNT:-1} x ${CONTROL_VCPUS:-4} vcpu / ${CONTROL_MEMORY_MB:-8192} MB / ${CONTROL_DISK_GB:-60} GB"
row "worker nodes" "${WORKER_COUNT:-2} x ${WORKER_VCPUS:-6} vcpu / ${WORKER_MEMORY_MB:-16384} MB / ${WORKER_DISK_GB:-100} GB"

info "cluster layer"
row "CLUSTER_VIP" "${CLUSTER_VIP:-${CLUSTER_SUBNET:-192.168.140}.10}"
row "POD_CIDR" "${POD_CIDR:-10.244.0.0/16}"
row "OS_PACK_VERSION" "edge-native-byoi ${OS_PACK_VERSION:-2.1.0} (Agent Mode)"
row "K8S_VERSION" "edge-k8s ${K8S_VERSION:-1.33.13} (PXK-E)"
row "CNI_VERSION" "cni-calico ${CNI_VERSION:-3.32.1}"
row "CSI_VERSION" "csi-local-path-provisioner ${CSI_VERSION:-0.0.37}"
if command -v tofu >/dev/null 2>&1; then
	row "OpenTofu" "$(tofu version 2>/dev/null | head -n1) (pinned ${TOFU_VERSION:-1.12.6})"
else
	row "OpenTofu" "MISSING. Run: just tofu-install"
fi

info "directories"
row "projects" "$(short_path "$(envs_dir)")"
row "API key" "$(short_path "$(api_key_file)")"
row "seeds" "$(short_path "$(data_dir)/seeds")"
row "build" "$(short_path "$(data_dir)/build")"
row "cloud image" "$(short_path "$(cache_dir)/images")"
if [ -n "${PALETTE_PROJECT:-}" ]; then
	row "OpenTofu state" "$(short_path "$(project_state_dir)")"
else
	row "OpenTofu state" "$(short_path "$(state_dir)")/<project>"
fi

# `scripts/dotenv.sh` reads the link and the justfile reads that script. Report
# the file that the link reaches, and name the correction when it reaches none.
link="$(env_link)"
if [ -f "$link" ]; then
	info "source: $(short_path "$(readlink -f "$link")") and the justfile defaults"
else
	info "source: the justfile defaults only"
	warn "there is no default project. Choose one: just default-project <name>"
fi
