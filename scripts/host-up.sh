#!/usr/bin/env bash
# Create and start one edge host VM.
#
# The boot order controls the installation. The system disk is boot.order=1 and
# the installer ISO is boot.order=2. The disk is empty at the first boot, so the
# firmware finds no boot loader and goes to the ISO. The Edge installer writes
# the disk. At the next boot the disk has a boot loader and the firmware uses
# it. The result is one installation and no installation loop.
#
# This script is idempotent. If the domain exists, the script starts it and
# stops. Run `just host-down NAME` to replace a host.
#
# Env: VCPUS MEMORY_MB DISK_GB NETWORK POOL ISO_DIR SEED_DIR
#
#   host-up.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"
: "${VCPUS:?}" "${MEMORY_MB:?}" "${DISK_GB:?}" "${NETWORK:?}" "${POOL:?}"
: "${ISO_DIR:?}" "${SEED_DIR:?}"

need virt-install
need virsh

if have_domain "$name"; then
	state="$(domain_state "$name")"
	if [ "$state" = "running" ]; then
		skip "domain $name is already running"
	else
		virsh start "$name" >/dev/null
		info "started the existing domain $name"
	fi
	exit 0
fi

seed="$SEED_DIR/$name-seed.iso"
[ -s "$seed" ] || die "no seed ISO for $name. Run: just seed $name"

# Use the newest installer ISO in the cache. iso-fetch.sh adds the version to
# each file name.
installer="$(find "$ISO_DIR" -maxdepth 1 -name 'palette-edge-installer-*.iso' -print0 2>/dev/null |
	xargs -0 -r ls -t | head -n1 || true)"
[ -n "$installer" ] || die "no installer ISO in $ISO_DIR. Run: just iso-fetch"

pool_dir="$(virsh pool-dumpxml "$POOL" | sed -n 's:.*<path>\(.*\)</path>.*:\1:p' | head -n1)"
[ -n "$pool_dir" ] || die "cannot read the target path of pool $POOL. Run: just pool-up"

info "create $name: ${VCPUS} vcpu, ${MEMORY_MB} MB, ${DISK_GB} GB, network $NETWORK"
info "installer: $(basename "$installer")"

# ANCHOR: virtinstall
virt-install \
	--name "$name" \
	--memory "$MEMORY_MB" \
	--vcpus "$VCPUS" \
	--cpu host-passthrough \
	--machine q35 \
	--boot uefi \
	--osinfo detect=on,require=off \
	--disk "path=$pool_dir/$name.qcow2,size=$DISK_GB,format=qcow2,bus=virtio,boot.order=1" \
	--disk "path=$installer,device=cdrom,readonly=on,boot.order=2" \
	--disk "path=$seed,device=cdrom,readonly=on" \
	--network "network=$NETWORK,model=virtio" \
	--graphics none \
	--console pty,target_type=serial \
	--rng /dev/urandom \
	--import \
	--noautoconsole
# ANCHOR_END: virtinstall

# The lab is a test tool. A host must not start with the workstation.
virsh autostart --disable "$name" >/dev/null 2>&1 || true

info "$name installs now. To watch it: just console $name"
