#!/usr/bin/env bash
# Prepare the workstation for a GitHub Actions runner.
#
# This is the only part of the runner that needs root, and it runs one time. It
# makes three things:
#
#   the user       an account that is not yours, with no sudo
#   the groups     libvirt and kvm, so the runner can make virtual machines
#   the directory  /var/lib/libvirt/images/$CI_CLUSTER, owned by that user
#
# The directory is the reason the runner needs no sudo of its own. `pool-up.sh`
# asks for root only when the pool directory is absent or not writable, so a
# directory that exists and belongs to the runner keeps every later recipe
# password free. See scripts/pool-up.sh.
#
# The runner user gets no entry in sudoers. Nothing in the build needs one.
#
# This script is idempotent.
#
# Env: RUNNER_USER RUNNER_HOME CI_CLUSTER
#
#   RUNNER_USER=ghrunner CI_CLUSTER=ci runner-setup.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

user="${RUNNER_USER:?runner user required}"
home="${RUNNER_HOME:-/home/$user}"
ci_cluster="${CI_CLUSTER:?ci cluster name required}"

target="/var/lib/libvirt/images/$ci_cluster"

# Every change below needs root. Ask for it one time, and say so before sudo
# prints a message that names no correction.
if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
	die "this recipe makes a user and a directory, so it needs root one time,
     and this session can neither ask for a password nor use a cached one.
     Run it again from a terminal."
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

for group in libvirt kvm; do
	if getent group "$group" >/dev/null 2>&1; then
		if id -nG "$user" | tr ' ' '\n' | grep -qx "$group"; then
			skip "$user is in the group $group"
		else
			sudo usermod -aG "$group" "$user" ||
				die "could not put $user in the group $group"
			info "put $user in the group $group"
		fi
	else
		warn "there is no group $group on this workstation.
         Install the virtualization packages first:  just host-setup"
	fi
done

# --- the pool directory -----------------------------------------------------

# libvirt owns /var/lib/libvirt/images and it belongs to root. The directory
# below belongs to the runner, so `just pool-up` finds it writable and asks for
# no password.
if [ -d "$target" ] && sudo test -O "$target" -o -w "$target" 2>/dev/null; then
	skip "$target exists"
else
	info "make $target for the CI lab"
	sudo mkdir -p "$target" ||
		die "could not make $target. Run: sudo mkdir -p $target"
fi

sudo chown "$user" "$target" ||
	die "could not give $target to $user. Run: sudo chown $user $target"
sudo chmod 0755 "$target"
info "$target belongs to $user"

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
