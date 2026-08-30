#!/usr/bin/env bash
# Configure the GitHub side of continuous integration.
#
# The repository is public, so a self-hosted runner needs gates. This script
# makes all of them, and each one closes a different path to your workstation:
#
#   1. main is protected, and a merge needs a review. The runner therefore
#      executes only code that a person approved. This is the gate that matters.
#   2. A fork pull request needs approval from a maintainer before any workflow
#      runs. Without it, a pull request can add a workflow of its own that names
#      the self-hosted runner.
#   3. The lab environment holds the Palette key and takes a reviewer. A job
#      that does not pass it gets no credentials.
#
# The e2e workflow names no `pull_request` trigger, so a fork cannot reach the
# runner even before these gates. They are the second and third answers.
#
# This script is idempotent. Each call sets the same state.
#
# Env: CI_ENVIRONMENT
#
#   ci-setup.sh
#   CI_ENVIRONMENT=lab ci-setup.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# `gh` is often a shell function in the environment of the person who calls
# this script, and an interactive function is not written for `set -u`. Every
# call below therefore uses `command`, which runs the program and not the
# function.
gh() { command gh "$@"; }


environment="${CI_ENVIRONMENT:-lab}"

command gh --version >/dev/null 2>&1 ||
	die "the GitHub CLI is not installed.
     Install it:  https://github.com/cli/cli#installation"
gh auth status >/dev/null 2>&1 || die "the GitHub CLI holds no credentials. Run: gh auth login"

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$repo" ] || die "cannot read the repository name. Run this recipe inside the checkout."

info "configure continuous integration for $repo"

# --- 1. protect main --------------------------------------------------------

# A merge needs one approving review, and the two hosted checks must pass. The
# self-hosted job runs after the merge, so it never sees unreviewed code.
if gh api -X PUT "repos/$repo/branches/main/protection" \
	--input - >/dev/null 2>&1 <<'JSON'; then
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["lint", "docs"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
	info "main is protected: a merge needs one review and the hosted checks"
else
	warn "could not protect main.
         The account needs administration rights on $repo.
         Set it by hand at Settings > Branches > Add rule."
fi

# --- 2. fork pull requests need approval ------------------------------------

# The API name for this is the workflow permissions of the repository. The
# setting itself lives in the Actions configuration.
if gh api -X PUT "repos/$repo/actions/permissions/access" \
	-f access_level=none >/dev/null 2>&1; then
	skip "workflow access from other repositories is closed"
fi

info "set fork pull requests to need approval"
printf '    The API does not carry this one. Set it at:\n'
printf '      https://github.com/%s/settings/actions\n' "$repo"
printf '      Fork pull request workflows from outside collaborators\n'
printf '      -> Require approval for all outside collaborators\n'

# --- 3. the lab environment -------------------------------------------------

# The environment gives a second gate and holds the Palette key. A deployment
# branch policy of main alone stops a job on any other branch from reaching it.
if gh api -X PUT "repos/$repo/environments/$environment" \
	--input - >/dev/null 2>&1 <<'JSON'; then
{
  "deployment_branch_policy": {
    "protected_branches": true,
    "custom_branch_policies": false
  }
}
JSON
	info "the environment $environment takes protected branches only"
else
	die "could not make the environment $environment.
     Make it by hand at Settings > Environments."
fi

# The Palette key. The environment holds it, so a job that does not pass the
# gate above never receives it.
key_file="$(api_key_file)"
if [ -s "$key_file" ]; then
	if gh secret set PALETTE_API_KEY --env "$environment" <"$key_file" >/dev/null 2>&1; then
		info "wrote the secret PALETTE_API_KEY to the environment $environment"
	else
		warn "could not write the secret. Set it by hand:
         gh secret set PALETTE_API_KEY --env $environment"
	fi
else
	warn "there is no API key on this workstation, so the secret stays empty.
         Store one, then run this recipe again:
           just api-key-set
         The end to end job cannot reach Palette until you do."
fi

printf '\n'
info "the GitHub side is ready"
printf '    Add a required reviewer to the environment, so a person approves each run:\n'
printf '      https://github.com/%s/settings/environments\n' "$repo"
printf '    Then start the runner:  just runner-setup && just runner-up\n'
