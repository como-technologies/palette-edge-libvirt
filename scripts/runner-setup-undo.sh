#!/usr/bin/env bash
# Remove the user, the groups, and the directory that `runner-setup.sh` made.
#
# This is the twin of runner-setup.sh. It refuses while the runner service is
# still installed, because that service belongs to the user that this script
# deletes. Run `just runner-down` first.
#
# The home directory holds the runner and its work directory. The script deletes
# it, so give FORCE=1 to answer the question in advance.
#
# This script is idempotent.
#
# Env: RUNNER_USER RUNNER_HOME CI_CLUSTER FORCE
#
#   runner-setup-undo.sh
#   FORCE=1 runner-setup-undo.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

user="${RUNNER_USER:?runner user required}"
home="${RUNNER_HOME:-/home/$user}"
ci_cluster="${CI_CLUSTER:?ci cluster name required}"

network="${ci_cluster}-net"
bridge="br-${ci_cluster}"
helper="${QEMU_BRIDGE_HELPER:-/usr/lib/qemu/qemu-bridge-helper}"

if ! id "$user" >/dev/null 2>&1; then
	skip "there is no user $user"
else
	# The service runs as this user. A user that goes while its service
	# stays leaves a unit that fails at every boot.
	if systemctl list-units --all --type=service --no-legend 2>/dev/null |
		grep -q 'actions\.runner\.'; then
		die "the runner service is still installed, and it runs as $user.
     Remove it first:  just runner-down"
	fi

	if [ "${FORCE:-0}" != "1" ]; then
		[ -t 0 ] || die "this deletes the user $user and the directory $home,
     and there is no terminal to ask.
     To delete them anyway:  FORCE=1 just runner-setup-undo"
		printf 'This deletes the user %s and its home directory %s.\n' "$user" "$home"
		printf 'Type yes to continue: '
		read -r answer
		[ "$answer" = "yes" ] || die "the answer was not yes. Nothing changed."
	fi

	sudo userdel --remove "$user" 2>/dev/null ||
		sudo userdel "$user" ||
		die "could not delete the user $user. Run: sudo userdel -r $user"
	info "deleted the user $user"
fi

# The pool of a session lab lives in the home directory of the runner, and the
# user delete above took it.

# --- the network of the CI lab ----------------------------------------------

if virsh -c qemu:///system net-info "$network" >/dev/null 2>&1; then
	NETWORK="$network" LIBVIRT_DEFAULT_URI=qemu:///system \
		"$(dirname "${BASH_SOURCE[0]}")/net-down.sh"
else
	skip "the network $network is absent"
fi

# --- the bridge helper ------------------------------------------------------
#
# Take the capability away and take this bridge out of the allowlist. Another
# bridge in that file belongs to somebody else, so remove the line and not the
# file.
if [ -x "$helper" ] && sudo getcap "$helper" 2>/dev/null | grep -q cap_net_admin; then
	if sudo setcap -r "$helper" 2>/dev/null; then
		info "took cap_net_admin off $helper"
	else
		warn "could not take the capability off $helper"
	fi
else
	skip "$helper has no capability of ours"
fi

if sudo test -f /etc/qemu/bridge.conf && sudo grep -qx "allow $bridge" /etc/qemu/bridge.conf; then
	sudo sed -i "/^allow ${bridge}\$/d" /etc/qemu/bridge.conf ||
		warn "could not take $bridge out of /etc/qemu/bridge.conf"
	info "took $bridge out of /etc/qemu/bridge.conf"
	# An empty allowlist is a file that allows nothing, which is the state
	# before this repository wrote it.
	if ! sudo grep -q . /etc/qemu/bridge.conf 2>/dev/null; then
		sudo rm -f /etc/qemu/bridge.conf
		info "removed the empty /etc/qemu/bridge.conf"
	fi
else
	skip "/etc/qemu/bridge.conf does not allow $bridge"
fi
