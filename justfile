# palette-edge-libvirt
#
# ANCHOR: rules
# Project rules:
#   1. Every action is a recipe. Do not run commands by hand.
#   2. Every recipe that creates an object has a recipe that removes it.
#   3. Every recipe is safe to run two or more times.
#   4. Every recipe has a documentation comment. The comment is the help text.
#   5. The documentation includes the source. It does not copy the source.
# ANCHOR_END: rules
#
# Run `just` to see all recipes. Run `just config` to see the current settings.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Every script of this repository prints its own error, and every message names
# the recipe that corrects the condition. `just` adds a line of its own after
# that message:
#
#   error: recipe `palette-hosts` failed on line 300 with exit code 1
#
# The line names a line of this file. It helps a person who edits the justfile,
# and it says nothing to a person who is using the tooling. It also comes last,
# so it is the line that stays on the screen while the correction scrolls away.
#
# The exit code stays, so a script that calls a recipe still sees the failure.
set no-exit-message

# The settings come from the environment file of the default project, and that
# file is in your home directory. A `set` takes a constant, so it can name no
# path there. It can name a command, and the command computes the path. The
# checkout therefore holds no configuration file at all.
#
# `just` runs the command from the justfile directory. With no default project
# the command prints nothing, and each recipe uses its default value.
set dotenv-command := 'scripts/dotenv.sh'

# --- configuration ----------------------------------------------------------
# Each variable has a default value, so the repository operates before you make
# a project. The environment file of the default project replaces these
# defaults. See templates/project.env for every value.

cluster := env_var_or_default("CLUSTER_NAME", "pe")
uri := env_var_or_default("LIBVIRT_DEFAULT_URI", "qemu:///system")
subnet := env_var_or_default("CLUSTER_SUBNET", "192.168.140")
ubuntu_release := env_var_or_default("UBUNTU_RELEASE", "noble")
ubuntu_image_url := env_var_or_default("UBUNTU_IMAGE_URL", "")
control_count := env_var_or_default("CONTROL_COUNT", "1")
control_vcpus := env_var_or_default("CONTROL_VCPUS", "4")
control_memory := env_var_or_default("CONTROL_MEMORY_MB", "8192")
control_disk := env_var_or_default("CONTROL_DISK_GB", "100")
worker_count := env_var_or_default("WORKER_COUNT", "2")
worker_vcpus := env_var_or_default("WORKER_VCPUS", "6")
worker_memory := env_var_or_default("WORKER_MEMORY_MB", "16384")
worker_disk := env_var_or_default("WORKER_DISK_GB", "100")

# The cluster layer. OpenTofu makes the cluster profile and the cluster.
tofu_version := env_var_or_default("TOFU_VERSION", "1.12.6")

# Palette refuses a cluster that gives no control plane endpoint, so this value
# is never empty. The address comes from the free range of the cluster subnet,
# below the DHCP pool. See docs/src/network.md.
cluster_vip := env_var_or_default("CLUSTER_VIP", subnet + ".10")

# The pod range. It must hold neither the cluster subnet nor the address of the
# workstation, and the pack default 192.168.0.0/16 holds both.
pod_cidr := env_var_or_default("POD_CIDR", "10.244.0.0/16")

# The packs are the combination under test, so each version is pinned. To see
# the versions that a pack offers now: just palette-packs edge-k8s
os_pack_version := env_var_or_default("OS_PACK_VERSION", "2.1.0")
k8s_version := env_var_or_default("K8S_VERSION", "1.33.13")
cni_version := env_var_or_default("CNI_VERSION", "3.32.1")
csi_version := env_var_or_default("CSI_VERSION", "0.0.37")
# `just cluster-verify` reads the cluster with kubectl. kubectl supports one
# minor version each side of the server, so this follows the pack by default.
kubectl_version := env_var_or_default("KUBECTL_VERSION", k8s_version)

# Continuous integration builds a lab of its own on the runner. The name and the
# subnet are fixed and OUTSIDE the range that new-project allocates
# (192.168.140 to 192.168.199), so a CI lab and a lab of yours never collide,
# and a teardown of one never frees the address of the other.
ci_cluster := env_var_or_default("CI_CLUSTER_NAME", "cilab")
ci_subnet := env_var_or_default("CI_CLUSTER_SUBNET", "192.168.210")
ci_vip := env_var_or_default("CI_CLUSTER_VIP", ci_subnet + ".10")

# The user that runs the GitHub Actions runner. It is not your account: it holds
# no sudo, and `just runner-setup` gives it the libvirt group and one pool
# directory.
runner_user := env_var_or_default("RUNNER_USER", "ghrunner")
runner_version := env_var_or_default("RUNNER_VERSION", "2.337.0")

# The checksum of the runner archive, pinned beside the version. A pinned
# checksum is what makes the download safe to run on your workstation.
# `just runner-pin` prints the pair for the current release.
runner_sha256 := env_var_or_default("RUNNER_SHA256", "70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613")
runner_home := env_var_or_default("RUNNER_HOME", "/home" / runner_user)

# The runner needs a `just` of its own. The one in your home directory belongs
# to you, and the Ubuntu package does not know `dotenv-command`. cargo installs
# it, exactly as the hosted workflow installs mdbook.
just_version := env_var_or_default("JUST_VERSION", "1.58.0")
runner_labels := env_var_or_default("RUNNER_LABELS", "self-hosted,linux,x64,kvm")

# ANCHOR: dirs
# The tooling directories. The checkout holds the source only. Delete the checkout
# and your projects, your tokens, and the downloaded image stay.
#
# Set a PEL_ variable in your shell to move a directory. The scripts read the
# same three variables, so a script that you call directly agrees with a recipe.
config_dir := env_var_or_default("PEL_CONFIG_DIR", config_directory() / "palette-edge-libvirt")
data_dir := env_var_or_default("PEL_DATA_DIR", data_directory() / "palette-edge-libvirt")
cache_dir := env_var_or_default("PEL_CACHE_DIR", cache_directory() / "palette-edge-libvirt")

# `just` has no state_directory() function, so this line builds the XDG state
# path itself. The OpenTofu state goes here, one directory for each project.
state_dir := env_var_or_default("PEL_STATE_DIR", env_var_or_default("XDG_STATE_HOME", home_directory() / ".local/state") / "palette-edge-libvirt")

# The tools that this repository installs for your user. OpenTofu goes here, so
# the install needs no root.
bin_dir := env_var_or_default("PEL_BIN_DIR", home_directory() / ".local/bin")

envs_dir := config_dir / "envs"
image_dir := cache_dir / "images"
seed_dir := data_dir / "seeds"
build_dir := data_dir / "build"
# ANCHOR_END: dirs

# Derived paths and names.
root := justfile_directory()
pool := cluster + "-pool"
net := cluster + "-net"

export LIBVIRT_DEFAULT_URI := uri
export PEL_CONFIG_DIR := config_dir
export PEL_DATA_DIR := data_dir
export PEL_STATE_DIR := state_dir
export PEL_CACHE_DIR := cache_dir
export PEL_BIN_DIR := bin_dir

# --- meta -------------------------------------------------------------------

# Show all recipes
default:
    @just --list --unsorted

# This recipe passes every value that it computed. config.sh therefore reports
# what the recipes use, and holds no second copy of a default that can drift
# away from the one above.
#
# The line below is the help text. `just --list` reads the LAST comment line
# before a recipe, so an explanation goes above it and never after it.

# Show the current configuration and its source
config:
    @CLUSTER_NAME="{{ cluster }}" CLUSTER_SUBNET="{{ subnet }}" \
        UBUNTU_RELEASE="{{ ubuntu_release }}" UBUNTU_IMAGE_URL="{{ ubuntu_image_url }}" \
        CONTROL_COUNT="{{ control_count }}" CONTROL_VCPUS="{{ control_vcpus }}" \
        CONTROL_MEMORY_MB="{{ control_memory }}" CONTROL_DISK_GB="{{ control_disk }}" \
        WORKER_COUNT="{{ worker_count }}" WORKER_VCPUS="{{ worker_vcpus }}" \
        WORKER_MEMORY_MB="{{ worker_memory }}" WORKER_DISK_GB="{{ worker_disk }}" \
        CLUSTER_VIP="{{ cluster_vip }}" POD_CIDR="{{ pod_cidr }}" \
        OS_PACK_VERSION="{{ os_pack_version }}" K8S_VERSION="{{ k8s_version }}" \
        CNI_VERSION="{{ cni_version }}" CSI_VERSION="{{ csi_version }}" \
        TOFU_VERSION="{{ tofu_version }}" \
        scripts/config.sh

# Test that the host has the necessary tools, permissions, and capacity
preflight:
    @scripts/preflight.sh

# --- host packages ----------------------------------------------------------

# ANCHOR: hostsetup
# Install libvirt, KVM, and the helper tools. Asks for the sudo password.
host-setup:
    sudo apt-get update
    sudo apt-get install -y \
        qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
        genisoimage curl shellcheck
    sudo usermod -aG libvirt,kvm "$USER"
    @echo
    @echo "The group membership changed. Restart the workstation."
    @echo "Make SSH access available first. These packages rebuild the initramfs,"
    @echo "and the screen can stay blank after the restart. See the docs at"
    @echo "docs/src/troubleshooting.md for the correction."
    @echo "After the restart, run: just preflight"

# ANCHOR_END: hostsetup

# Remove the packages that host-setup installed. Asks for the sudo password.
host-setup-undo:
    sudo apt-get remove -y \
        qemu-kvm libvirt-daemon-system libvirt-clients virtinst genisoimage
    sudo apt-get autoremove -y
    -sudo gpasswd -d "$USER" libvirt
    -sudo gpasswd -d "$USER" kvm

# --- infrastructure layer ---------------------------------------------------
# Layer 1. The network, the storage pool, the virtual machines, and the Palette
# record of each host. The layer is complete when every host registers, because
# that record is the only thing that the cluster layer can use.

# ANCHOR: infraup
# Create the machines and wait until every host registers with Palette
infra-up: preflight net-up pool-up image-fetch
    #!/usr/bin/env bash
    set -euo pipefail
    for i in $(seq 1 {{ control_count }}); do
        just seed "{{ cluster }}-cp-$i"
        just host-up "{{ cluster }}-cp-$i" control
    done
    for i in $(seq 1 {{ worker_count }}); do
        just seed "{{ cluster }}-wk-$i"
        just host-up "{{ cluster }}-wk-$i" worker
    done
    echo
    just hosts-wait

# Remove the host records, the machines, the pool, and the network
infra-down:
    @CLUSTER="{{ cluster }}" POOL="{{ pool }}" NETWORK="{{ net }}" scripts/infra-down.sh
# ANCHOR_END: infraup

# Wait until every host of this cluster registers with Palette
hosts-wait:
    @CLUSTER="{{ cluster }}" scripts/hosts-wait.sh

# Remove the Palette record of every host of this cluster. The machines stay.
hosts-deregister:
    @CLUSTER="{{ cluster }}" scripts/hosts-deregister.sh

# --- infrastructure parts ---------------------------------------------------

# Create and start the isolated NAT network for the cluster
net-up:
    @NETWORK="{{ net }}" CLUSTER="{{ cluster }}" SUBNET="{{ subnet }}" BUILD_DIR="{{ build_dir }}" scripts/net-up.sh

# Stop and remove the cluster network
net-down:
    @NETWORK="{{ net }}" scripts/net-down.sh

# Create and start the storage pool for the VM disks
pool-up:
    @POOL="{{ pool }}" CLUSTER="{{ cluster }}" scripts/pool-up.sh

# Stop and remove the storage pool. Keeps the disk images.
pool-down:
    @POOL="{{ pool }}" scripts/pool-down.sh

# --- host image -------------------------------------------------------------

# Download the stock Ubuntu cloud image and test its checksum
image-fetch:
    @scripts/image-fetch.sh "{{ ubuntu_release }}" "{{ ubuntu_image_url }}" "{{ image_dir }}"

# Delete the downloaded cloud image
image-clean:
    @if [ -d "{{ image_dir }}" ]; then \
        rm -rf "{{ image_dir }}"; echo "==> removed {{ image_dir }}"; \
    else echo "    {{ image_dir }} is absent"; fi

# --- seeds ------------------------------------------------------------------

# Build the cloud-init seed ISO that registers NAME with Palette
seed host:
    @scripts/seed-iso.sh "{{ host }}" "{{ seed_dir }}" "{{ build_dir }}"

# Build a seed ISO for each node in the topology
seed-all:
    @CONTROL_COUNT="{{ control_count }}" WORKER_COUNT="{{ worker_count }}" CLUSTER="{{ cluster }}" \
        scripts/for-each-node.sh just seed

# Delete all seed ISO files and the build directory
seed-clean:
    @for d in "{{ seed_dir }}" "{{ build_dir }}"; do \
        if [ -d "$d" ]; then rm -rf "$d"; echo "==> removed $d"; \
        else echo "    $d is absent"; fi; \
    done

# --- hosts ------------------------------------------------------------------

# Create one host VM. ROLE is control or worker and sets the size.
host-up host role="worker":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ role }}" in
      control) vcpus={{ control_vcpus }}; mem={{ control_memory }}; disk={{ control_disk }} ;;
      worker)  vcpus={{ worker_vcpus }};  mem={{ worker_memory }};  disk={{ worker_disk }} ;;
      *) echo "error: role must be control or worker. You gave '{{ role }}'." >&2; exit 2 ;;
    esac
    VCPUS="$vcpus" MEMORY_MB="$mem" DISK_GB="$disk" \
    NETWORK="{{ net }}" POOL="{{ pool }}" IMAGE_DIR="{{ image_dir }}" SEED_DIR="{{ seed_dir }}" \
        scripts/host-up.sh "{{ host }}"

# Stop one host VM, remove it, and delete its disk
host-down host:
    @POOL="{{ pool }}" scripts/host-down.sh "{{ host }}"

# Show the progress of the agent installation on one host
host-status host:
    @scripts/host-status.sh "{{ host }}"

# Remove the Palette record of a host. The VM stays.
host-deregister host:
    @scripts/host-deregister.sh "{{ host }}"

# Remove the seed ISO from a host after the agent installs
host-eject host:
    @scripts/host-eject.sh "{{ host }}"

# Open the serial console of a host. Press ctrl-] to exit.
console host:
    @scripts/host-console.sh "{{ host }}"

# Show the DHCP address of a host
ip host:
    @scripts/host-ip.sh "{{ host }}"

# List all VMs in this cluster and their state
ls:
    @scripts/cluster-ls.sh "{{ cluster }}"

# --- credentials ------------------------------------------------------------

# Store the Palette API key outside the checkout. Reads it without an echo.
api-key-set:
    @scripts/api-key.sh set

# Report whether a Palette API key is stored, and its length only
api-key-status:
    @scripts/api-key.sh status

# Delete the stored Palette API key
api-key-clear:
    @scripts/api-key.sh clear

# --- projects ---------------------------------------------------------------

# List the projects that have an environment file. The * marks the default.
projects:
    @scripts/project-ls.sh

# Create a Palette project, write its environment file, and make it the default
new-project project description="":
    @scripts/project-new.sh "{{ project }}" "{{ description }}"

# Delete a Palette project and its environment file. Asks before it deletes.
remove-project project:
    @scripts/project-remove.sh "{{ project }}"

# Select the project that every recipe operates on
default-project project:
    @scripts/project-default.sh "{{ project }}"

# --- palette ----------------------------------------------------------------

# List the projects in your tenant and test PALETTE_PROJECT
palette-projects:
    @scripts/palette-api.sh projects

# List the hosts that registered with your Palette project
palette-hosts:
    @scripts/palette-api.sh hosts

# List the registration tokens and the project each one registers into
palette-tokens:
    @scripts/palette-api.sh tokens

# List the clusters in your Palette project
palette-clusters:
    @scripts/palette-api.sh clusters

# List the versions of one Edge Native pack in the public registry
palette-packs pack:
    @scripts/palette-api.sh packs "{{ pack }}"

# --- cluster layer ----------------------------------------------------------
# Layer 2. The cluster profile and the cluster, both in Palette. OpenTofu builds
# this layer from the hosts that layer 1 registered. See docs/src/cluster.md.

# ANCHOR: clusterup
# Create the cluster profile and the cluster from the registered hosts
cluster-up: (_tofu "apply")

# Remove the cluster and the cluster profile. The hosts and the machines stay.
cluster-down: (_tofu "destroy")

# Show the changes that cluster-up would make. Changes nothing.
cluster-plan: (_tofu "plan")

# ANCHOR_END: clusterup

# Test that the cluster works: the nodes, the pod range, the packs, and DNS
cluster-verify:
    @CLUSTER="{{ cluster }}" CONTROL_COUNT="{{ control_count }}" \
        WORKER_COUNT="{{ worker_count }}" K8S_VERSION="{{ k8s_version }}" \
        POD_CIDR="{{ pod_cidr }}" CLUSTER_SUBNET="{{ subnet }}" \
        CLUSTER_VIP="{{ cluster_vip }}" TOFU_VERSION="{{ tofu_version }}" \
        CNI_VERSION="{{ cni_version }}" CSI_VERSION="{{ csi_version }}" \
        OS_PACK_VERSION="{{ os_pack_version }}" \
        scripts/cluster-verify.sh

# Show the cluster profile, the cluster, and the link to the Palette console
cluster-show: (_tofu "output")

# Print the administrator kubeconfig. Send it to a file: just cluster-kubeconfig > k
cluster-kubeconfig: (_tofu "kubeconfig")

# The one entry point to OpenTofu. Every cluster recipe passes through it, so
# the state path, the credentials, and the host list are computed one time.
[private]
_tofu action:
    @TOFU_VERSION="{{ tofu_version }}" CLUSTER="{{ cluster }}" CLUSTER_VIP="{{ cluster_vip }}" \
        CLUSTER_SUBNET="{{ subnet }}" POD_CIDR="{{ pod_cidr }}" \
        K8S_VERSION="{{ k8s_version }}" CNI_VERSION="{{ cni_version }}" \
        CSI_VERSION="{{ csi_version }}" OS_PACK_VERSION="{{ os_pack_version }}" \
        CONTROL_COUNT="{{ control_count }}" WORKER_COUNT="{{ worker_count }}" \
        scripts/cluster.sh "{{ action }}"

# --- opentofu ---------------------------------------------------------------

# Install the pinned OpenTofu into ~/.local/bin. Needs no root.
tofu-install:
    @TOFU_VERSION="{{ tofu_version }}" BIN_DIR="{{ bin_dir }}" CACHE_DIR="{{ cache_dir }}/tofu" \
        scripts/tofu-install.sh

# Remove the OpenTofu that tofu-install put in ~/.local/bin
tofu-uninstall:
    @BIN_DIR="{{ bin_dir }}" CACHE_DIR="{{ cache_dir }}/tofu" scripts/tofu-uninstall.sh

# --- kubectl ----------------------------------------------------------------

# Install kubectl for the pinned Kubernetes version into ~/.local/bin. No root.
kubectl-install:
    @KUBECTL_VERSION="{{ kubectl_version }}" BIN_DIR="{{ bin_dir }}" \
        CACHE_DIR="{{ cache_dir }}/kubectl" scripts/kubectl-install.sh

# Remove the kubectl that kubectl-install put in ~/.local/bin
kubectl-uninstall:
    @BIN_DIR="{{ bin_dir }}" CACHE_DIR="{{ cache_dir }}/kubectl" scripts/kubectl-uninstall.sh

# --- continuous integration -------------------------------------------------
# The runner is a process on this workstation, not a virtual machine, so the
# cluster nodes it builds run on bare metal. See docs/src/ci.md.

# ANCHOR: runner
# Make the runner user, its groups, and its pool directory. Needs root one time.
runner-setup:
    @RUNNER_USER="{{ runner_user }}" RUNNER_HOME="{{ runner_home }}" \
        CI_CLUSTER="{{ ci_cluster }}" JUST_VERSION="{{ just_version }}" \
        scripts/runner-setup.sh

# Remove the runner user and its pool directory. Asks before it deletes.
runner-setup-undo:
    @RUNNER_USER="{{ runner_user }}" RUNNER_HOME="{{ runner_home }}" \
        CI_CLUSTER="{{ ci_cluster }}" scripts/runner-setup-undo.sh

# Install and start the GitHub Actions runner as a systemd service
runner-up:
    @RUNNER_USER="{{ runner_user }}" RUNNER_HOME="{{ runner_home }}" \
        RUNNER_VERSION="{{ runner_version }}" RUNNER_SHA256="{{ runner_sha256 }}" \
        RUNNER_LABELS="{{ runner_labels }}" CACHE_DIR="{{ cache_dir }}/runner" \
        scripts/runner-up.sh

# Stop the runner, remove its service, and take it out of the repository
runner-down:
    @RUNNER_USER="{{ runner_user }}" RUNNER_HOME="{{ runner_home }}" \
        scripts/runner-down.sh
# ANCHOR_END: runner

# Print the CI lab settings as an environment file
#
# The workflow reads this into GITHUB_ENV, so the settings of the CI lab live
# here and in no second place. A workflow that repeated them would drift away
# from these, exactly as `just config` once reported a disk size that the
# recipes did not use.
ci-env:
    @echo "CLUSTER_NAME={{ ci_cluster }}"
    @echo "CLUSTER_SUBNET={{ ci_subnet }}"
    @echo "CLUSTER_VIP={{ ci_vip }}"
    @echo "POD_CIDR={{ pod_cidr }}"

# Show the state of the runner service and its registration
runner-status:
    @scripts/runner-status.sh

# Print the version and the checksum of the current runner release
runner-pin:
    @scripts/runner-pin.sh

# Protect main, make the lab environment, and store the Palette key in it
ci-setup:
    @scripts/ci-setup.sh

# Remove the lab environment and the protection of main. Asks first.
ci-setup-undo:
    @scripts/ci-setup-undo.sh

# --- everything -------------------------------------------------------------

# ANCHOR: nuke
# Remove every object of this project: both layers, the token, and the project
nuke: cluster-down infra-down
    @scripts/nuke.sh
# ANCHOR_END: nuke

# --- docs -------------------------------------------------------------------

# Test that the generated theme files are present.
#
# `just docs-theme-clean` removes them, and mdbook then stops with "failed to
# open `gruvbox/css/variables.css` for hashing", which names no correction. The
# files are committed, so this fires only after that recipe.
[private]
_docs-theme-check:
    @for f in docs/gruvbox/css/variables.css docs/mermaid.min.js docs/mermaid-init.js; do \
        if [ ! -f "$f" ]; then \
            echo "error: the docs theme file $f is absent." >&2; \
            echo "     To write the theme files again:  just docs-theme" >&2; \
            exit 1; \
        fi; \
    done

# Build the mdBook site into docs/book
docs: _docs-theme-check
    mdbook build docs

# Build the docs and serve them at http://localhost:3000 with live reload
docs-serve: _docs-theme-check
    mdbook serve docs --open

# Delete the built docs
docs-clean:
    mdbook clean docs

# Install the mermaid and gruvbox theme files into docs/
docs-theme:
    mdbook-mermaid install docs
    mdbook-gruvbox install docs

# Delete the installed theme files. Run docs-theme to restore them.
docs-theme-clean:
    @rm -rf docs/gruvbox docs/mermaid.min.js docs/mermaid-init.js
    @echo "==> removed the theme files. To write them again: just docs-theme"

# --- shell ------------------------------------------------------------------

# Print the bash completion. Use: source <(just bash-completion)
bash-completion:
    @scripts/bash-completion.sh print

# Install the bash completion for your user and print its path
bash-completion-install:
    @scripts/bash-completion.sh install

# Remove the installed bash completion
bash-completion-uninstall:
    @scripts/bash-completion.sh uninstall

# --- quality ----------------------------------------------------------------

# Format the justfile
fmt:
    just --fmt

# Test the format, the recipes, the shell scripts, and the docs build
lint: _docs-theme-check
    just --fmt --check
    @scripts/lint-pairs.sh
    @scripts/lint-params.sh
    @scripts/lint-includes.sh
    @scripts/lint-shell.sh
    mdbook build docs
