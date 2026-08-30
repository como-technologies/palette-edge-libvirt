#!/usr/bin/env bash
# Create and start one cluster host VM.
#
# The host boots a copy of the stock Ubuntu cloud image. There is no operating
# system installation and no installer media. cloud-init reads the seed ISO at
# the first boot, installs the Palette agent, and the agent registers the host.
#
# The script copies the cloud image for each host. A copy costs about one second
# on an NVMe disk, and it keeps each host independent. qemu-img then grows the
# copy to the requested size. cloud-init grows the file system to fill it.
#
# This script is idempotent. If the domain exists, the script starts it and
# stops. Run `just host-down NAME` to replace a host.
#
# Env: VCPUS MEMORY_MB DISK_GB NETWORK POOL IMAGE_DIR SEED_DIR
#
#   host-up.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"
: "${VCPUS:?}" "${MEMORY_MB:?}" "${DISK_GB:?}" "${NETWORK:?}" "${POOL:?}"
: "${IMAGE_DIR:?}" "${SEED_DIR:?}"

need virt-install
need virsh
need qemu-img

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

# Use the newest cloud image in the cache.
image="$(find "$IMAGE_DIR" -maxdepth 1 -name '*-server-cloudimg-amd64.img' -print0 2>/dev/null |
	xargs -0 -r ls -t | head -n1 || true)"
[ -n "$image" ] || die "no cloud image in $IMAGE_DIR. Run: just image-fetch"

pool_dir="$(virsh pool-dumpxml "$POOL" | sed -n 's:.*<path>\(.*\)</path>.*:\1:p' | head -n1)"
[ -n "$pool_dir" ] || die "cannot read the target path of pool $POOL. Run: just pool-up"
[ -w "$pool_dir" ] || die "cannot write to $pool_dir. Run: just pool-up"

disk="$pool_dir/$name.qcow2"

# The seed ISO lives in seeds/, and that directory is mode 0700 because it
# holds the registration token. The qemu user cannot enter it, so a domain that
# reads the seed from there fails to start:
#
#   Could not open '.../seeds/NAME-seed.iso': Permission denied
#
# The answer is not to open seeds/ to every user. libvirt owns the pool
# directory and gives the qemu user access to the files in it, so the seed goes
# there as well. The copy keeps mode 0600, and `just host-down` deletes it.
seed_in_pool="$pool_dir/$name-seed.iso"

info "create $name: ${VCPUS} vcpu, ${MEMORY_MB} MB, ${DISK_GB} GB, network $NETWORK"
info "image: $(basename "$image")"

# Copy the image, then grow it. The cloud image is about 600 MB. qcow2 files
# are sparse, so the grown file uses only the space that the host writes.
qemu-img convert -f qcow2 -O qcow2 "$image" "$disk"
qemu-img resize -q "$disk" "${DISK_GB}G"

install -m 0600 "$seed" "$seed_in_pool"

# ANCHOR: virtinstall
# --import boots the disk that already holds an operating system. There is no
# installation phase and no boot order to manage.
virt-install \
	--name "$name" \
	--memory "$MEMORY_MB" \
	--vcpus "$VCPUS" \
	--cpu host-passthrough \
	--machine q35 \
	--osinfo detect=on,require=off \
	--disk "path=$disk,format=qcow2,bus=virtio" \
	--disk "path=$seed_in_pool,device=cdrom,readonly=on" \
	--network "network=$NETWORK,model=virtio" \
	--graphics none \
	--console pty,target_type=serial \
	--rng /dev/urandom \
	--import \
	--noautoconsole
# ANCHOR_END: virtinstall

# This is a test tool. A host must not start with the workstation.
virsh autostart --disable "$name" >/dev/null 2>&1 || true

info "$name starts now. To watch it: just console $name"
