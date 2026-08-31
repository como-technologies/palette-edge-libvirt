#!/usr/bin/env bash
# Prepare the workstation for a GitHub Actions runner.
#
# This is the only part of the runner that needs root, and it runs one time:
#
#   the user       an account that is not yours, with no sudo
#   the group      kvm, and NOT libvirt
#   the network    one system network, because a session daemon makes none
#   the helper     cap_net_admin on qemu-bridge-helper, and one bridge in
#                  /etc/qemu/bridge.conf
#
# The runner drives the SESSION daemon, qemu:///session, which runs as the
# runner itself. That is the whole point of this script. A member of the
# `libvirt` group drives the system daemon, which runs as root, and can give a
# domain the disk of the workstation: that membership is the same as root, and
# no sudoers file changes it. The runner is not in that group, so the privilege
# of a build stops at the runner account.
#
# A session cannot make a network, so root makes one here and the session
# domains take its bridge. The bridge carries the subnet, the DHCP server, and
# the address that kube-vip claims, exactly as it does for a lab of yours.
#
# This script is idempotent.
#
# Env: RUNNER_USER RUNNER_HOME CI_CLUSTER CI_SUBNET JUST_VERSION
#
#   RUNNER_USER=ghrunner CI_CLUSTER=cilab CI_SUBNET=192.168.210 runner-setup.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

user="${RUNNER_USER:?runner user required}"
home="${RUNNER_HOME:-/home/$user}"
ci_cluster="${CI_CLUSTER:?ci cluster name required}"
ci_subnet="${CI_SUBNET:?ci subnet required}"
here="$(dirname "${BASH_SOURCE[0]}")"

network="${ci_cluster}-net"
bridge="br-${ci_cluster}"
helper="${QEMU_BRIDGE_HELPER:-/usr/lib/qemu/qemu-bridge-helper}"

# Every change below needs root. Ask for it one time, and say so before sudo
# prints a message that names no correction.
if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
	die "this recipe makes a user and a directory, so it needs root one time,
     and this session can neither ask for a password nor use a cached one.
     Give sudo the password first, then run the recipe again:
       sudo -v && just runner-setup
     A shell inside an editor or an agent is not a terminal either, so the
     same two commands work there."
fi

# --- the user ---------------------------------------------------------------

if id "$user" >/dev/null 2>&1; then
	skip "the user $user exists"
else
	info "make the user $user"
	sudo useradd --create-home --home-dir "$home" --shell /bin/bash "$user" ||
		die "could not make the user $user. Run: sudo useradd -m -d $home -s /bin/bash $user"
	info "made $user with the home directory $home"
fi

# --- the groups -------------------------------------------------------------
#
# `kvm` only, and NOT `libvirt`.
#
# The socket of the system daemon is root:libvirt and libvirtd.conf sets
# auth_unix_rw to "none", so a member of that group drives a daemon that runs as
# root. Such a member can define a domain whose disk is the disk of the
# workstation, start it, and read and write every file on it. The group is the
# same as root, whatever the sudoers file says.
#
# The runner therefore takes the SESSION daemon, which runs as the runner. It
# opens the files that the runner can open and no others.
if id -nG "$user" | tr ' ' '\n' | grep -qx libvirt; then
	sudo gpasswd -d "$user" libvirt >/dev/null ||
		warn "could not take $user out of the group libvirt. Run: sudo gpasswd -d $user libvirt"
	info "took $user out of the group libvirt, which is the same as root"

	# A process takes its groups when it starts. The runner service is
	# already running with the old set, so it keeps the group until it
	# starts again, and a report of "not in the group" would be wrong.
	if systemctl list-units --all --type=service --no-legend 2>/dev/null |
		grep -q 'actions\.runner\.'; then
		warn "the runner service still runs with the old groups.
         A process takes its groups when it starts, so restart it:
           just runner-down && just runner-up"
	fi
fi

if getent group kvm >/dev/null 2>&1; then
	if id -nG "$user" | tr ' ' '\n' | grep -qx kvm; then
		skip "$user is in the group kvm"
	else
		sudo usermod -aG kvm "$user" || die "could not put $user in the group kvm"
		info "put $user in the group kvm, for /dev/kvm"
	fi
else
	warn "there is no group kvm on this workstation.
         Install the virtualization packages first:  just host-setup"
fi

# --- the network of the CI lab ----------------------------------------------
#
# A session daemon makes no network. A bridge, NAT, and dnsmasq need root, so
# root makes one system network here, one time, and the session domains take its
# bridge. The network brings the subnet, the DHCP server, and the address that
# kube-vip claims.
if virsh -c qemu:///system net-info "$network" >/dev/null 2>&1; then
	skip "the network $network exists"
else
	info "make the system network $network for the CI lab"
	NETWORK="$network" CLUSTER="$ci_cluster" SUBNET="$ci_subnet" \
		BUILD_DIR="${BUILD_DIR:-$(data_dir)/build}" \
		LIBVIRT_DEFAULT_URI=qemu:///system "$here/net-up.sh" >/dev/null ||
		die "could not make the network $network"
	info "made $network on ${ci_subnet}.0/24, bridge $bridge"
fi

# --- the bridge helper ------------------------------------------------------
#
# A session domain attaches its tap to the bridge through qemu-bridge-helper.
# Ubuntu ships that program with no setuid bit and no capability, on purpose, so
# root grants the one capability that it needs. /etc/qemu/bridge.conf then names
# the bridges that any account may join, and it names this one only.
if [ ! -x "$helper" ]; then
	warn "there is no $helper, so a session domain reaches no bridge.
         Install the qemu-system-x86 package:  just host-setup"
elif sudo getcap "$helper" 2>/dev/null | grep -q cap_net_admin; then
	skip "$helper has cap_net_admin"
else
	sudo setcap cap_net_admin+ep "$helper" ||
		die "could not give cap_net_admin to $helper.
     Run: sudo setcap cap_net_admin+ep $helper"
	info "gave cap_net_admin to $helper"
fi

if sudo grep -qx "allow $bridge" /etc/qemu/bridge.conf 2>/dev/null; then
	skip "/etc/qemu/bridge.conf allows $bridge"
else
	info "allow $bridge in /etc/qemu/bridge.conf"
	sudo mkdir -p /etc/qemu
	sudo sh -c "printf 'allow %s\\n' '$bridge' >> /etc/qemu/bridge.conf" ||
		die "could not write /etc/qemu/bridge.conf"
	sudo chmod 0644 /etc/qemu/bridge.conf
fi

# --- the pool directory -----------------------------------------------------
#
# A session pool lives in the home directory of the runner, so this needs no
# root and no directory under /var/lib/libvirt.
skip "the session pool goes in the home directory of $user, so it needs no root"

# --- a just that the runner can reach ---------------------------------------
#
# `just` is a Rust program, so cargo installs it, exactly as the hosted
# workflow installs mdbook. The runner needs its own copy for two reasons: the
# one in your home directory belongs to you and no other user may depend on it,
# and the Ubuntu package does not know `dotenv-command`, so it cannot read this
# justfile at all.
#
# cargo and the crate both go in the home directory of the runner, so this step
# needs no root. `--locked` takes the dependency versions of the release.
just_version="${JUST_VERSION:?just version required}"
cargo="$home/.cargo/bin/cargo"

if sudo -u "$user" test -x "$cargo"; then
	skip "$user has cargo"
else
	info "install rustup and cargo for $user"
	sudo -u "$user" env HOME="$home" bash -c '
		set -euo pipefail
		curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs |
			sh -s -- -y --no-modify-path --profile minimal
	' || die "could not install rustup for $user.
     See https://rustup.rs and install it as that user."
	info "installed cargo for $user"
fi

# `cargo install` reports "already installed" and returns 0, so a second run of
# this recipe compiles nothing.
info "install just $just_version for $user with cargo"
sudo -u "$user" env HOME="$home" "$cargo" install --locked --version "$just_version" just ||
	die "cargo could not install just $just_version for $user.
     To see the reason:  sudo -u $user $cargo install --locked --version $just_version just"

installed="$(sudo -u "$user" env HOME="$home" "$home/.cargo/bin/just" --version 2>/dev/null |
	awk '{ print $2 }' || true)"
[ "$installed" = "$just_version" ] ||
	die "$home/.cargo/bin/just reports '$installed' and not $just_version"
info "$user has just $just_version at $home/.cargo/bin/just"

# --- the tools that the build needs -----------------------------------------

# The runner shell is not a login shell, so it reads no profile. Every tool
# below must therefore sit on the default PATH.
missing=()
for tool in git virsh virt-install qemu-img genisoimage curl python3 tar; do
	command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
	warn "these tools are not on the system PATH: ${missing[*]}
         The runner reads no profile, so it needs each one there.
         Run: just host-setup"
fi

printf '\n'
info "the workstation is ready for the runner. Next: just runner-up"
printf '    The user %s has no sudo, and the build needs none.\n' "$user"
