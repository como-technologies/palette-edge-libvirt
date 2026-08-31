#!/usr/bin/env bash
# Install and start the GitHub Actions runner as a systemd service.
#
# The runner is a process on this workstation, and not a virtual machine. It
# therefore makes the cluster machines on bare metal, with no second level of
# virtualization, and it reserves no memory while it waits.
#
# The registration is PERSISTENT. An ephemeral runner takes one job and then
# removes its own registration, so a service that starts it again needs a stored
# GitHub token with rights to make runners. This repository stores no such
# token: the cleanliness of each build comes from `just nuke`, which the
# workflow runs before and after every job.
#
# The registration token comes from the API at the moment of use and lives for
# one hour. Nothing writes it to disk.
#
# The archive checksum is pinned in the justfile. That is what makes it safe to
# run this code on your workstation.
#
# This script is idempotent. It reports a skip when the service is installed.
#
# Env: RUNNER_USER RUNNER_HOME RUNNER_VERSION RUNNER_SHA256 RUNNER_LABELS
#      RUNNER_NAME CACHE_DIR
#
#   runner-up.sh

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
version="${RUNNER_VERSION:?runner version required}"
want_sha="${RUNNER_SHA256:?runner checksum required}"
labels="${RUNNER_LABELS:-self-hosted,linux,x64,kvm}"
name="${RUNNER_NAME:-$(hostname -s)}"
cache="${CACHE_DIR:-$(cache_dir)/runner}"

need curl
need tar

command gh --version >/dev/null 2>&1 ||
	die "the GitHub CLI is not installed, and this recipe reads the registration
     token with it.
     Install it:  https://github.com/cli/cli#installation
     Then sign in:  gh auth login"

gh auth status >/dev/null 2>&1 ||
	die "the GitHub CLI holds no credentials. Run: gh auth login"

id "$user" >/dev/null 2>&1 ||
	die "there is no user $user. Run: just runner-setup"

dir="$home/actions-runner"

# --- is it there already ----------------------------------------------------
#
# Two states, and they are not the same. The service is the last step, so a run
# that stopped part of the way leaves a runner that is registered and has no
# service. `config.sh` then refuses to register a second time, and an earlier
# version of this script died there on every retry.

service_installed() {
	[ -n "$(runner_units)" ]
}

# config.sh writes .runner when it registers. The file belongs to the runner
# user, so the test needs sudo.
registered_here() {
	sudo test -f "$dir/.runner"
}

# A unit that names a runner directory with no `.service` marker is the leaving
# of a removal that did not finish. svc.sh reads that marker to know its own
# unit name, so it can neither start nor remove this one, and `svc.sh install`
# refuses while the file is there. Clear it and carry on.
if service_installed && ! sudo test -f "$dir/.service"; then
	info "remove a runner unit that an earlier run left"
	for unit in $(runner_units); do
		sudo systemctl disable --now "$(basename "$unit")" >/dev/null 2>&1 || true
		sudo rm -f "$unit"
		info "removed $unit"
	done
	sudo systemctl daemon-reload
fi

if service_installed; then
	skip "a runner service is installed already"
	for unit in $(runner_units); do
		printf '    %s %s\n' "$(basename "$unit")" \
			"$(systemctl is-active "$(basename "$unit")" 2>/dev/null || true)"
	done
	exit 0
fi

# --- the repository ---------------------------------------------------------

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$repo" ] || die "cannot read the repository name. Run this recipe inside the checkout."

# --- the archive ------------------------------------------------------------

archive="actions-runner-linux-x64-${version}.tar.gz"
url="https://github.com/actions/runner/releases/download/v${version}/${archive}"

mkdir -p "$cache"

if [ -s "$cache/$archive" ] &&
	[ "$(sha256sum "$cache/$archive" | cut -d' ' -f1)" = "$want_sha" ]; then
	skip "the cache holds a correct $archive"
else
	info "download the runner $version"
	curl -fL --retry 3 -o "$cache/${archive}.part" "$url" ||
		die "cannot read $url. Check RUNNER_VERSION."
	mv "$cache/${archive}.part" "$cache/$archive"

	got_sha="$(sha256sum "$cache/$archive" | cut -d' ' -f1)"
	[ "$got_sha" = "$want_sha" ] || {
		rm -f "$cache/$archive"
		die "the downloaded $archive does not match the pinned checksum.
     pinned: $want_sha
     read:   $got_sha
     A version change needs a checksum change. Run: just runner-pin"
	}
	info "checksum correct"
fi

# --- unpack -----------------------------------------------------------------

if sudo test -x "$dir/config.sh"; then
	skip "the runner files are in $dir"
else
	info "unpack the runner into $dir"
	sudo -u "$user" mkdir -p "$dir"
	sudo -u "$user" tar -xzf "$cache/$archive" -C "$dir" ||
		die "could not unpack $archive into $dir"
fi

# --- register ---------------------------------------------------------------

if registered_here; then
	skip "the runner is registered already, so this run installs the service only"
	printf '    To register it again:  just runner-down && just runner-up\n'
else
	# The token lives for one hour and registers one runner. It goes to the
	# command line of a process that runs as the runner user, and to no file.
	info "read a registration token for $repo"
	token="$(gh api -X POST "repos/$repo/actions/runners/registration-token" -q .token 2>/dev/null || true)"
	[ -n "$token" ] ||
		die "cannot read a registration token for $repo.
     The account needs administration rights on the repository.
     To test:  gh api repos/$repo/actions/runners --jq '.total_count'"

	# --replace takes the name of a runner that GitHub still holds, which is
	# what an earlier run leaves when it loses its files.
	info "register the runner $name with the labels $labels"
	sudo -u "$user" env RUNNER_ALLOW_RUNASROOT=0 \
		"$dir/config.sh" \
		--unattended \
		--url "https://github.com/$repo" \
		--token "$token" \
		--name "$name" \
		--labels "$labels" \
		--work "_work" \
		--replace ||
		die "the runner did not register.
     To see the state:      just runner-status
     To start from empty:   just runner-down && just runner-up"
fi

# --- the service ------------------------------------------------------------

# `svc.sh` reads the files beside it, so it needs the runner directory as the
# working directory. The `cd` therefore happens INSIDE sudo: the home directory
# of the runner does not admit the person who calls this recipe, and a `cd` that
# runs as that person fails with "Permission denied" before sudo starts.
info "install the systemd service"
sudo bash -c 'cd "$1" && ./svc.sh install "$2"' _ "$dir" "$user" ||
	die "could not install the service. Run:
       sudo bash -c 'cd $dir && ./svc.sh install $user'"

sudo bash -c 'cd "$1" && ./svc.sh start' _ "$dir" ||
	die "could not start the service. Run:
       sudo bash -c 'cd $dir && ./svc.sh start'"

printf '\n'
info "the runner is up. To see it: just runner-status"
printf '    The workflow reaches it with:  runs-on: [%s]\n' "${labels//,/, }"
printf '    It runs no job until you protect main and make the lab environment:\n'
printf '      just ci-setup\n'
