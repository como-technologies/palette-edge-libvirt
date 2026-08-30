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

if systemctl list-units --all --type=service --no-legend 2>/dev/null |
	grep -q 'actions\.runner\.'; then
	skip "a runner service is installed already"
	systemctl list-units --all --type=service --no-legend |
		grep 'actions\.runner\.' | awk '{ printf "    %s %s\n", $1, $4 }'
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

# The token lives for one hour and registers one runner. It goes to the command
# line of a process that runs as the runner user, and to no file.
info "read a registration token for $repo"
token="$(gh api -X POST "repos/$repo/actions/runners/registration-token" -q .token 2>/dev/null || true)"
[ -n "$token" ] ||
	die "cannot read a registration token for $repo.
     The account needs administration rights on the repository.
     To test:  gh api repos/$repo/actions/runners --jq '.total_count'"

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
	die "the runner did not register. To see the state: just runner-status"

# --- the service ------------------------------------------------------------

info "install the systemd service"
(cd "$dir" && sudo ./svc.sh install "$user") ||
	die "could not install the service. Run: cd $dir && sudo ./svc.sh install $user"

(cd "$dir" && sudo ./svc.sh start) ||
	die "could not start the service. Run: cd $dir && sudo ./svc.sh start"

printf '\n'
info "the runner is up. To see it: just runner-status"
printf '    The workflow reaches it with:  runs-on: [%s]\n' "${labels//,/, }"
printf '    It runs no job until you protect main and make the lab environment:\n'
printf '      just ci-setup\n'
