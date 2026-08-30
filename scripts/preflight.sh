#!/usr/bin/env bash
# Test that the workstation can run the cluster.
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

# The cluster layer needs OpenTofu. Ubuntu does not package it, so it has a
# recipe of its own and not a line in host-setup.
if command -v tofu >/dev/null; then
	check "tofu" yes "$(tofu version 2>/dev/null | head -n1)"
else
	check "tofu" no "" "run: just tofu-install"
fi

# The hosts boot a stock cloud image with the standard firmware. The cluster needs
# no UEFI firmware package.

info "libvirt"

# in_db: the group database gives this group to the user.
in_db() { id -nG "$USER" | tr ' ' '\n' | grep -qx "$1"; }
# in_session: this process has this group now.
in_session() { id -nG | tr ' ' '\n' | grep -qx "$1"; }

# A new group applies only to a new login session. The group database can hold
# the group while the current shell does not. The libvirt socket then refuses
# the connection, and the reason is not obvious.
#
# This test covers the libvirt group only. The libvirt group gates the socket.
# The kvm group has no test here, because the /dev/kvm access test above
# measures that capability directly. On some systems udev gives access to
# /dev/kvm without the kvm group.
# manager_stale: the systemd user manager is older than the group database.
#
# systemd-logind keeps the user manager while one process of the user runs. The
# default setting KillUserProcesses=no permits this. The manager then holds the
# group list from its own start time. Every new shell is a child of the manager,
# so a new login gives the same old group list. Only a restart of the manager
# corrects it.
manager_stale() {
	command -v systemctl >/dev/null 2>&1 || return 1
	local started changed
	started="$(systemctl show "user@$(id -u).service" -P ActiveEnterTimestamp 2>/dev/null)"
	[ -n "$started" ] || return 1
	started="$(date -d "$started" +%s 2>/dev/null)" || return 1
	changed="$(stat -c %Y /etc/group 2>/dev/null)" || return 1
	[ "$started" -lt "$changed" ]
}

stale=""
if ! in_db libvirt; then
	check "libvirt group" no "" "you are not in the libvirt group. Run: just host-setup"
elif ! in_session libvirt; then
	stale=yes
	if manager_stale; then
		check "libvirt group" no "" \
			"the systemd user manager is older than the group. Restart the workstation."
	else
		check "libvirt group" no "" \
			"the group database has it, but this session does not. Log out and log in again."
	fi
else
	check "libvirt group" yes "this session has the group"
fi

# One of these units gives the socket. The name depends on the libvirt version.
if systemctl is-active --quiet libvirtd.socket ||
	systemctl is-active --quiet virtqemud.socket ||
	systemctl is-active --quiet libvirtd; then
	check "daemon" yes "the libvirt socket is active"
else
	check "daemon" no "" "run: sudo systemctl enable --now libvirtd.socket"
fi

uri="${LIBVIRT_DEFAULT_URI:-qemu:///system}"
if virsh -c "$uri" version >/dev/null 2>&1; then
	check "connection" yes "$uri"
elif [ -n "$stale" ]; then
	check "connection" no "" "$uri refuses this session. See the libvirt group line."
else
	check "connection" no "" "cannot reach $uri"
fi

info "palette"
# The API key, and the length only. Never print the key.
#
# Every recipe that reaches the API needs it, and the token below is not a
# substitute: the token registers a host, and the key is what reads the project,
# the hosts, and the clusters. A preflight that passes without it sends you to
# the first API call to find out.
if [ -s "$(api_key_file)" ]; then
	key="$(cat "$(api_key_file)")"
	check "API key" yes "the key file holds ${#key} characters"
elif [ -n "${PALETTE_API_KEY:-}" ]; then
	check "API key" yes "the environment holds ${#PALETTE_API_KEY} characters"
else
	check "API key" no "" "run: just api-key-set"
fi
if [ -n "${PALETTE_EDGE_TOKEN:-}" ]; then
	# Print the length only. Never print the token.
	check "PALETTE_EDGE_TOKEN" yes "set (${#PALETTE_EDGE_TOKEN} characters)"
else
	check "PALETTE_EDGE_TOKEN" no "" "run: just new-project <name>"
fi
check "PALETTE_ENDPOINT" yes "${PALETTE_ENDPOINT:-api.spectrocloud.com}"
if [ -n "${PALETTE_PROJECT:-}" ]; then
	check "PALETTE_PROJECT" yes "${PALETTE_PROJECT}"
else
	check "PALETTE_PROJECT" no "" "not set. Run: just palette-projects, then just default-project"
fi

info "capacity"
cpus=$(nproc)
mem_gb=$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / 1024 / 1024 / 1024))
want_cpu=$((${CONTROL_COUNT:-1} * ${CONTROL_VCPUS:-4} + ${WORKER_COUNT:-2} * ${WORKER_VCPUS:-6}))
want_mem=$(((${CONTROL_COUNT:-1} * ${CONTROL_MEMORY_MB:-8192} + ${WORKER_COUNT:-2} * ${WORKER_MEMORY_MB:-16384}) / 1024))

printf '  info  %-24s %s vcpu, %s GB\n' "topology needs" "$want_cpu" "$want_mem"
printf '  info  %-24s %s cpu, %s GB\n' "workstation has" "$cpus" "$mem_gb"

# The host can oversubscribe the CPU safely. It cannot oversubscribe the memory.
if [ "$want_mem" -ge "$mem_gb" ]; then
	warn "the topology needs all of the memory. Lower WORKER_COUNT or WORKER_MEMORY_MB."
fi

if [ "$fail" -eq 0 ]; then
	info "the workstation is ready"
fi

exit "$fail"
