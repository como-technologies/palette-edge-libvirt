#!/usr/bin/env bash
# Remove the GitHub side of continuous integration.
#
# This is the twin of ci-setup.sh. It removes the environment, its secret, and
# the protection of main.
#
# The protection of main is a safety feature of the repository and not only a
# part of CI, so this script asks before it removes that one. Give FORCE=1 to
# answer in advance.
#
# This script is idempotent.
#
# Env: CI_ENVIRONMENT FORCE
#
#   ci-setup-undo.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# `gh` is often a shell function in the environment of the person who calls
# this script, and an interactive function is not written for `set -u`. Every
# call below therefore uses `command`, which runs the program and not the
# function.
gh() { command gh "$@"; }


environment="${CI_ENVIRONMENT:-lab}"

command gh --version >/dev/null 2>&1 || die "the GitHub CLI is not installed."
gh auth status >/dev/null 2>&1 || die "the GitHub CLI holds no credentials. Run: gh auth login"

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$repo" ] || die "cannot read the repository name. Run this recipe inside the checkout."

# --- the environment and its secret -----------------------------------------

if gh api "repos/$repo/environments/$environment" >/dev/null 2>&1; then
	gh secret delete PALETTE_API_KEY --env "$environment" >/dev/null 2>&1 || true
	if gh api -X DELETE "repos/$repo/environments/$environment" >/dev/null 2>&1; then
		info "removed the environment $environment and its secret"
	else
		warn "could not remove the environment $environment"
	fi
else
	skip "there is no environment $environment"
fi

# --- the protection of main -------------------------------------------------

if ! gh api "repos/$repo/branches/main/protection" >/dev/null 2>&1; then
	skip "main is not protected"
	exit 0
fi

# A public repository with no protection on main takes a direct push from every
# person with write rights, and the self-hosted runner then executes it.
if [ "${FORCE:-0}" != "1" ]; then
	[ -t 0 ] || die "this removes the protection of main, and the runner then
     executes code that no person reviewed. There is no terminal to ask.
     To remove it anyway:  FORCE=1 just ci-setup-undo"
	printf 'This removes the branch protection of main.\n'
	printf 'The self-hosted runner then executes any code that reaches main.\n'
	printf 'Type yes to continue: '
	read -r answer
	[ "$answer" = "yes" ] || die "the answer was not yes. The protection stays."
fi

if gh api -X DELETE "repos/$repo/branches/main/protection" >/dev/null 2>&1; then
	info "removed the protection of main"
else
	warn "could not remove the protection of main"
fi
