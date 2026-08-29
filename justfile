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
set dotenv-load

# --- configuration ----------------------------------------------------------
# Each variable has a default value. The repository operates before you make
# the .env file. Values in .env replace these defaults. See .env.example.

lab := env_var_or_default("LAB_NAME", "pe")
uri := env_var_or_default("LIBVIRT_DEFAULT_URI", "qemu:///system")
subnet := env_var_or_default("LAB_SUBNET", "192.168.140")
palette_endpoint := env_var_or_default("PALETTE_ENDPOINT", "api.spectrocloud.com")
palette_project := env_var_or_default("PALETTE_PROJECT", "Default")
palette_token := env_var_or_default("PALETTE_EDGE_TOKEN", "")
installer_version := env_var_or_default("EDGE_INSTALLER_VERSION", "v4.7.6")
installer_url := env_var_or_default("EDGE_INSTALLER_URL", "")
control_count := env_var_or_default("CONTROL_COUNT", "1")
control_vcpus := env_var_or_default("CONTROL_VCPUS", "4")
control_memory := env_var_or_default("CONTROL_MEMORY_MB", "8192")
control_disk := env_var_or_default("CONTROL_DISK_GB", "60")
worker_count := env_var_or_default("WORKER_COUNT", "2")
worker_vcpus := env_var_or_default("WORKER_VCPUS", "6")
worker_memory := env_var_or_default("WORKER_MEMORY_MB", "16384")
worker_disk := env_var_or_default("WORKER_DISK_GB", "100")

# Derived paths and names.
root := justfile_directory()
iso_dir := root / "iso"
seed_dir := root / "seeds"
build_dir := root / "build"
pool := lab + "-pool"
net := lab + "-net"

export LIBVIRT_DEFAULT_URI := uri

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

# Install libvirt, KVM, and the helper tools. Asks for the sudo password.
host-setup:
    sudo apt-get update
    sudo apt-get install -y \
        qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
        ovmf genisoimage curl shellcheck
    sudo usermod -aG libvirt,kvm "$USER"
    @echo
    @echo "The group membership changed. Log out and log in again."
    @echo "Then run: just preflight"

# Remove the packages that host-setup installed. Asks for the sudo password.
host-setup-undo:
    sudo apt-get remove -y \
        qemu-kvm libvirt-daemon-system libvirt-clients virtinst ovmf genisoimage
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
    @NETWORK="{{ net }}" SUBNET="{{ subnet }}" BUILD_DIR="{{ build_dir }}" scripts/net-up.sh

# Stop and remove the lab network
net-down:
    @NETWORK="{{ net }}" scripts/net-down.sh

# Create and start the storage pool for the VM disks
pool-up:
    @POOL="{{ pool }}" LAB="{{ lab }}" scripts/pool-up.sh

# Stop and remove the storage pool. Keeps the disk images.
pool-down:
    @POOL="{{ pool }}" scripts/pool-down.sh

# --- installer media --------------------------------------------------------

# Download the Palette Edge installer ISO into iso/
iso-fetch:
    @scripts/iso-fetch.sh "{{ installer_version }}" "{{ installer_url }}" "{{ iso_dir }}"

# Delete the downloaded installer ISO files
iso-clean:
    rm -rf "{{ iso_dir }}"

# --- seeds ------------------------------------------------------------------

# Build the cloud-init seed ISO that registers NAME with Palette
seed name:
    @scripts/seed-iso.sh "{{ name }}" "{{ seed_dir }}" "{{ build_dir }}"

# Build a seed ISO for each node in the topology
seed-all:
    @CONTROL_COUNT="{{ control_count }}" WORKER_COUNT="{{ worker_count }}" LAB="{{ lab }}" \
        scripts/for-each-node.sh just seed

# Delete all seed ISO files and the build directory
seed-clean:
    rm -rf "{{ seed_dir }}" "{{ build_dir }}"

# --- edge hosts -------------------------------------------------------------

# Create one edge host VM. ROLE is control or worker and sets the size.
host-up name role="worker":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ role }}" in
      control) vcpus={{ control_vcpus }}; mem={{ control_memory }}; disk={{ control_disk }} ;;
      worker)  vcpus={{ worker_vcpus }};  mem={{ worker_memory }};  disk={{ worker_disk }} ;;
      *) echo "error: role must be control or worker. You gave '{{ role }}'." >&2; exit 2 ;;
    esac
    VCPUS="$vcpus" MEMORY_MB="$mem" DISK_GB="$disk" \
    NETWORK="{{ net }}" POOL="{{ pool }}" ISO_DIR="{{ iso_dir }}" SEED_DIR="{{ seed_dir }}" \
        scripts/host-up.sh "{{ name }}"

# Stop one edge host VM, remove it, and delete its disk
host-down name:
    @scripts/host-down.sh "{{ name }}"

# Remove the installer ISO from a host after the installation is complete
host-eject name:
    @scripts/host-eject.sh "{{ name }}"

# Open the serial console of a host. Press ctrl-] to exit.
console name:
    virsh console "{{ name }}"

# Show the DHCP address of a host
ip name:
    @scripts/host-ip.sh "{{ name }}"

# List all VMs in this lab and their state
ls:
    @scripts/lab-ls.sh "{{ lab }}"

# --- cluster ----------------------------------------------------------------

# ANCHOR: clusterup
# Create the full lab: infrastructure, installer ISO, seeds, and all nodes
cluster-up: preflight infra-up iso-fetch
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
    echo "The hosts install now. To watch one host: just console {{ lab }}-cp-1"
    echo "The hosts show in Palette at Clusters > Edge Hosts after they register."

# Remove all VMs in the lab. Keeps the network, the pool, and the ISO.
cluster-down:
    @LAB="{{ lab }}" scripts/cluster-down.sh

# Remove everything this repository creates, except the downloaded ISO
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

# --- quality ----------------------------------------------------------------

# Format the justfile
fmt:
    just --fmt

# Test the format, the shell scripts, and the documentation build
lint:
    just --fmt --check
    @scripts/lint-shell.sh
    mdbook build docs
