#!/usr/bin/env bash
# Test that the workstation can run the lab.
#
# The script makes no change. It prints ok or FAIL for each item. It stops with
# a failure code if one item fails. `just cluster-up` runs this script first.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fail=0

# check <label> <yes|no> <detail-when-ok> <detail-when-failed>
check() {
	local label="$1" ok="$2" good="${3:-}" bad="${4:-}"
	if [ "$ok" = "yes" ]; then
		printf '  ok    %-24s %s\n' "$label" "$good"
	else
		printf '  FAIL  %-24s %s\n' "$label" "$bad"
		fail=1
	fi
}

info "host"

[ -e /dev/kvm ] && kvm=yes || kvm=no
check "/dev/kvm" "$kvm" \
	"the CPU gives hardware virtualization" \
	"enable VT-x or AMD-V in the BIOS"

[ -r /dev/kvm ] && [ -w /dev/kvm ] && kvmrw=yes || kvmrw=no
check "/dev/kvm access" "$kvmrw" \
	"you can read and write the device" \
	"join the kvm group, then log out and log in again"

for bin in virsh virt-install qemu-img curl; do
	command -v "$bin" >/dev/null && has=yes || has=no
	check "$bin" "$has" \
		"$(command -v "$bin" 2>/dev/null || true)" \
		"run: just host-setup"
done

# The seed ISO needs one of these two tools.
if command -v genisoimage >/dev/null || command -v xorriso >/dev/null; then
	check "iso tool" yes "$(command -v genisoimage || command -v xorriso)"
else
	check "iso tool" no "" "install genisoimage or xorriso"
fi

# The Edge installer images boot UEFI, so the host needs the OVMF firmware.
if compgen -G "/usr/share/OVMF/OVMF_CODE*.fd" >/dev/null; then
	check "OVMF (UEFI)" yes "/usr/share/OVMF"
else
	check "OVMF (UEFI)" no "" "install the ovmf package"
fi

info "libvirt"
uri="${LIBVIRT_DEFAULT_URI:-qemu:///system}"
if virsh -c "$uri" version >/dev/null 2>&1; then
	check "connection" yes "$uri"
else
	check "connection" no "" "cannot reach $uri"
fi

info "palette"
if [ -n "${PALETTE_EDGE_TOKEN:-}" ]; then
	# Print the length only. Never print the token.
	check "PALETTE_EDGE_TOKEN" yes "set (${#PALETTE_EDGE_TOKEN} characters)"
else
	check "PALETTE_EDGE_TOKEN" no "" "copy .env.example to .env and add the token"
fi
check "PALETTE_ENDPOINT" yes "${PALETTE_ENDPOINT:-api.spectrocloud.com}"
check "PALETTE_PROJECT" yes "${PALETTE_PROJECT:-Default}"

info "capacity"
cpus=$(nproc)
mem_gb=$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / 1024 / 1024 / 1024))
want_cpu=$((${CONTROL_COUNT:-1} * ${CONTROL_VCPUS:-4} + ${WORKER_COUNT:-2} * ${WORKER_VCPUS:-6}))
want_mem=$(((${CONTROL_COUNT:-1} * ${CONTROL_MEMORY_MB:-8192} + ${WORKER_COUNT:-2} * ${WORKER_MEMORY_MB:-16384}) / 1024))

printf '  info  %-24s %s vcpu, %s GB\n' "topology needs" "$want_cpu" "$want_mem"
printf '  info  %-24s %s cpu, %s GB\n' "workstation has" "$cpus" "$mem_gb"

# The host can oversubscribe the CPU safely. It cannot oversubscribe the memory.
if [ "$want_mem" -ge "$mem_gb" ]; then
	warn "the topology needs all of the memory. Lower WORKER_COUNT or WORKER_MEMORY_MB in .env."
fi

if [ "$fail" -eq 0 ]; then
	info "the workstation is ready"
fi

exit "$fail"
