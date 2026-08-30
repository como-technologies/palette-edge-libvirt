#!/usr/bin/env bash
# Show the configuration that the recipes use now.
#
# The justfile takes each value from the environment file of the default project
# or from its own default, and then passes every one of them to this script. So
# this script holds no default of its own: it reports what it receives.
#
# An earlier version repeated each default here. One of them drifted, and
# `just config` reported a 60 GB control plane disk while the recipes built a
# 100 GB one. A value that has two sources has two answers.
#
# A value that arrives empty prints as "unset", which is what you see when you
# call this script directly instead of through the recipe.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

row() { printf '  %-22s %s\n' "$1" "${2:-unset}"; }

cluster="${CLUSTER_NAME:-unset}"

info "cluster"
row "CLUSTER_NAME" "$cluster"
row "network" "${cluster}-net (${CLUSTER_SUBNET:-unset}.0/24)"
row "pool" "${cluster}-pool"
row "LIBVIRT_DEFAULT_URI" "${LIBVIRT_DEFAULT_URI:-}"

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
row "UBUNTU_RELEASE" "${UBUNTU_RELEASE:-}"
row "UBUNTU_IMAGE_URL" "${UBUNTU_IMAGE_URL:-(derived from the release)}"

info "topology"
row "control nodes" "${CONTROL_COUNT:-?} x ${CONTROL_VCPUS:-?} vcpu / ${CONTROL_MEMORY_MB:-?} MB / ${CONTROL_DISK_GB:-?} GB"
row "worker nodes" "${WORKER_COUNT:-?} x ${WORKER_VCPUS:-?} vcpu / ${WORKER_MEMORY_MB:-?} MB / ${WORKER_DISK_GB:-?} GB"

info "cluster layer"
row "CLUSTER_VIP" "${CLUSTER_VIP:-}"
row "POD_CIDR" "${POD_CIDR:-}"
row "OS_PACK_VERSION" "edge-native-byoi ${OS_PACK_VERSION:-?} (Agent Mode)"
row "K8S_VERSION" "edge-k8s ${K8S_VERSION:-?} (PXK-E)"
row "CNI_VERSION" "cni-calico ${CNI_VERSION:-?}"
row "CSI_VERSION" "csi-local-path-provisioner ${CSI_VERSION:-?}"
if command -v tofu >/dev/null 2>&1; then
	row "OpenTofu" "$(tofu version 2>/dev/null | head -n1) (pinned ${TOFU_VERSION:-?})"
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
