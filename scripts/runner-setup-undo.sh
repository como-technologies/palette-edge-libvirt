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

target="/var/lib/libvirt/images/$ci_cluster"

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

# The pool directory of the CI lab. `just infra-down` removes the files in it,
# and rmdir refuses a directory that still holds one.
if [ ! -d "$target" ]; then
	skip "$target is absent"
elif sudo rmdir "$target" 2>/dev/null; then
	info "removed $target"
else
	warn "$target still holds a file, so it stays.
         Remove the CI lab first:  CLUSTER_NAME=$ci_cluster just infra-down"
fi
