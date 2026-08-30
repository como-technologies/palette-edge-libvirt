#!/usr/bin/env bash
# Shared functions for the lab scripts. Source this file. Do not execute it.

set -euo pipefail

# die: print an error message and stop with a failure code.
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

# info: print a progress message.
info() {
	printf '==> %s\n' "$*"
}

# warn: print a warning message. Does not stop the script.
warn() {
	printf 'warning: %s\n' "$*" >&2
}

# ANCHOR: skip
# skip: print a message when a recipe finds no work to do.
# The lab recipes are idempotent. A second run reports a skip and returns 0.
skip() {
	printf '    %s\n' "$*"
}
# ANCHOR_END: skip

# need: stop the script if a command is not available.
need() {
	command -v "$1" >/dev/null 2>&1 ||
		die "$1 is not installed. Run: just host-setup"
}

# need_project: put the project name in PALETTE_PROJECT, or stop.
#
# There is no default. A tenant need not have a project called "Default", and a
# tenant can delete it. A recipe that guesses a project name sends hosts to the
# wrong place, and Palette reports no error when it does.
need_project() {
	if [ -z "${PALETTE_PROJECT:-}" ]; then
		die "PALETTE_PROJECT is empty. There is no default project.
     To see the projects in your tenant:  just palette-projects
     To make a project and its file:      just new-project <name>
     To select one that exists:           just default-project <name>"
	fi
}

# api_key_file: print the path of the Palette API key file.
#
# The key lives outside the checkout on purpose. It is a tenant credential, so
# no project recipe may delete it, and `just nuke` must not reach it.
api_key_file() {
	printf '%s/palette-edge-libvirt/api-key\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# repo_root: print the absolute path of the checkout, from any directory.
repo_root() {
	cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# have_domain: return 0 if libvirt knows the given domain.
have_domain() {
	virsh dominfo "$1" >/dev/null 2>&1
}

# domain_state: print the state of a domain, or "absent".
domain_state() {
	virsh domstate "$1" 2>/dev/null || printf 'absent\n'
}
