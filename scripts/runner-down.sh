#!/usr/bin/env bash
# Stop the runner service, remove it, and take the runner out of the repository.
#
# This is the twin of runner-up.sh. It reverses all three of its steps: the
# service, the registration in GitHub, and the files.
#
# The removal token comes from the API at the moment of use, exactly as the
# registration token does. A runner that loses its files without this step stays
# in the repository as an offline runner, and a later `runner-up` then makes a
# second one.
#
# The user and the pool directory stay. `just runner-setup-undo` removes those.
#
# This script is idempotent.
#
# Env: RUNNER_USER RUNNER_HOME
#
#   runner-down.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# `gh` is often a shell function in the environment of the person who calls
# this script, and an interactive function is not written for `set -u`. Every
# call below therefore uses `command`, which runs the program and not the
# function.
gh() { command gh "$@"; }


user="${RUNNER_USER:?runner user required}"
home="${RUNNER_HOME:-/home/$user}"

dir="$home/actions-runner"

if ! id "$user" >/dev/null 2>&1; then
	skip "there is no user $user"
	exit 0
fi

if ! sudo test -d "$dir"; then
	skip "there is no runner in $dir"
	exit 0
fi

# --- the service ------------------------------------------------------------

if [ -n "$(runner_units)" ]; then
	# The `cd` runs inside sudo. The home directory of the runner does not
	# admit the person who calls this recipe, so a `cd` outside sudo fails
	# with "Permission denied" before sudo starts.
	sudo bash -c 'cd "$1" && ./svc.sh stop' _ "$dir" >/dev/null 2>&1 || true
	info "stopped the runner service"
	if sudo bash -c 'cd "$1" && ./svc.sh uninstall' _ "$dir" >/dev/null 2>&1; then
		info "removed the runner service"
	fi

	# svc.sh reads $dir/.service to find its own unit, so it removes
	# nothing when that marker is gone. Take any unit that is left.
	for unit in $(runner_units); do
		sudo systemctl disable --now "$(basename "$unit")" >/dev/null 2>&1 || true
		sudo rm -f "$unit"
		info "removed $unit"
	done
	sudo systemctl daemon-reload
else
	skip "no runner service is installed"
fi

# --- the registration -------------------------------------------------------

# A runner that keeps its record in GitHub shows as offline for ever, and the
# name is then taken. Remove the record while the files can still prove who it
# is.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
	repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
	if [ -n "$repo" ]; then
		token="$(gh api -X POST "repos/$repo/actions/runners/remove-token" -q .token 2>/dev/null || true)"
		if [ -n "$token" ]; then
			if sudo -u "$user" "$dir/config.sh" remove --token "$token" >/dev/null 2>&1; then
				info "removed the runner from $repo"
			else
				warn "the runner keeps its record in $repo.
         Remove it at Settings > Actions > Runners."
			fi
		else
			warn "cannot read a removal token for $repo.
         Remove the runner at Settings > Actions > Runners."
		fi
	fi
else
	warn "the GitHub CLI holds no credentials, so the record stays in GitHub.
         Remove it at Settings > Actions > Runners."
fi

# --- the files --------------------------------------------------------------

sudo rm -rf "$dir"
info "removed $dir"

printf '\n'
printf '    The user %s and its pool directory stay.\n' "$user"
printf '    To remove those as well:  just runner-setup-undo\n'
