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

# .env in the checkout is a link to ~/.config/palette-edge-libvirt/env, and that
# link points at the environment file of the default project. `set dotenv-path`
# takes a constant, so it cannot name the home directory. The link supplies the
# path. An absent or broken link loads nothing and reports no error, so the
# recipes still run on their default values.
set dotenv-path := ".env"

# --- configuration ----------------------------------------------------------
# Each variable has a default value. The repository operates before you make
# the .env file. Values in .env replace these defaults. See .env.example.

lab := env_var_or_default("LAB_NAME", "pe")
uri := env_var_or_default("LIBVIRT_DEFAULT_URI", "qemu:///system")
subnet := env_var_or_default("LAB_SUBNET", "192.168.140")
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

# ANCHOR: dirs
# The lab directories. The checkout holds the source only. Delete the checkout
# and your projects, your tokens, and the downloaded image stay.
#
# Set a PEL_ variable in your shell to move a directory. The scripts read the
# same three variables, so a script that you call directly agrees with a recipe.
config_dir := env_var_or_default("PEL_CONFIG_DIR", config_directory() / "palette-edge-libvirt")
data_dir := env_var_or_default("PEL_DATA_DIR", data_directory() / "palette-edge-libvirt")
cache_dir := env_var_or_default("PEL_CACHE_DIR", cache_directory() / "palette-edge-libvirt")

envs_dir := config_dir / "envs"
image_dir := cache_dir / "images"
seed_dir := data_dir / "seeds"
build_dir := data_dir / "build"
# ANCHOR_END: dirs

# Derived paths and names.
root := justfile_directory()
pool := lab + "-pool"
net := lab + "-net"

export LIBVIRT_DEFAULT_URI := uri
export PEL_CONFIG_DIR := config_dir
export PEL_DATA_DIR := data_dir
export PEL_CACHE_DIR := cache_dir

# --- meta -------------------------------------------------------------------

# Show all recipes
default:
    @just --list --unsorted

# Show the current configuration and its source
config:
    @scripts/config.sh

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

# --- libvirt infrastructure -------------------------------------------------

# Create the lab network and the lab storage pool
infra-up: net-up pool-up

# Remove the lab network and the lab storage pool. Removes no VMs.
infra-down: pool-down net-down

# Create and start the isolated NAT network for the lab
net-up:
    @NETWORK="{{ net }}" LAB="{{ lab }}" SUBNET="{{ subnet }}" BUILD_DIR="{{ build_dir }}" scripts/net-up.sh

# Stop and remove the lab network
net-down:
    @NETWORK="{{ net }}" scripts/net-down.sh

# Create and start the storage pool for the VM disks
pool-up:
    @POOL="{{ pool }}" LAB="{{ lab }}" scripts/pool-up.sh

# Stop and remove the storage pool. Keeps the disk images.
pool-down:
    @POOL="{{ pool }}" scripts/pool-down.sh

# --- host image -------------------------------------------------------------

# Download the stock Ubuntu cloud image and test its checksum
image-fetch:
    @scripts/image-fetch.sh "{{ ubuntu_release }}" "{{ ubuntu_image_url }}" "{{ image_dir }}"

# Delete the downloaded cloud image
image-clean:
    rm -rf "{{ image_dir }}"

# --- seeds ------------------------------------------------------------------

# Build the cloud-init seed ISO that registers NAME with Palette
seed host:
    @scripts/seed-iso.sh "{{ host }}" "{{ seed_dir }}" "{{ build_dir }}"

# Build a seed ISO for each node in the topology
seed-all:
    @CONTROL_COUNT="{{ control_count }}" WORKER_COUNT="{{ worker_count }}" LAB="{{ lab }}" \
        scripts/for-each-node.sh just seed

# Delete all seed ISO files and the build directory
seed-clean:
    rm -rf "{{ seed_dir }}" "{{ build_dir }}"

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
    virsh console "{{ host }}"

# Show the DHCP address of a host
ip host:
    @scripts/host-ip.sh "{{ host }}"

# List all VMs in this lab and their state
ls:
    @scripts/lab-ls.sh "{{ lab }}"

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

# Move a regular .env from the checkout into the project layout
adopt-project project:
    @scripts/project-adopt.sh "{{ project }}"

# Make .env a regular file in the checkout again. The twin of adopt-project.
unadopt-project:
    @scripts/project-unadopt.sh

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

# --- cluster ----------------------------------------------------------------

# ANCHOR: clusterup
# Create the full lab: infrastructure, image, seeds, and all hosts
cluster-up: preflight infra-up image-fetch
    #!/usr/bin/env bash
    set -euo pipefail
    for i in $(seq 1 {{ control_count }}); do
        just seed "{{ lab }}-cp-$i"
        just host-up "{{ lab }}-cp-$i" control
    done
    for i in $(seq 1 {{ worker_count }}); do
        just seed "{{ lab }}-wk-$i"
        just host-up "{{ lab }}-wk-$i" worker
    done
    echo
    echo "The hosts boot now. cloud-init installs the agent, which takes minutes."
    echo "To watch one host:   just console {{ lab }}-cp-1"
    echo "To test registration: just palette-hosts"

# Remove all VMs in the lab. Keeps the network, the pool, and the image.
cluster-down:
    @LAB="{{ lab }}" POOL="{{ pool }}" scripts/cluster-down.sh

# Remove everything this repository creates, except the downloaded image
nuke: cluster-down infra-down seed-clean
# ANCHOR_END: clusterup

# --- docs -------------------------------------------------------------------

# Build the mdBook site into docs/book
docs:
    mdbook build docs

# Build the docs and serve them at http://localhost:3000 with live reload
docs-serve:
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
    rm -rf docs/gruvbox docs/mermaid.min.js docs/mermaid-init.js

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
lint:
    just --fmt --check
    @scripts/lint-pairs.sh
    @scripts/lint-params.sh
    @scripts/lint-shell.sh
    mdbook build docs
