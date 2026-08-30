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

# ANCHOR: dirs
# The lab directories.
#
# The checkout holds the source only. Every file that you want to keep lives in
# one of three directories outside it, so `rm -rf` on the checkout destroys no
# project, no token, and no download.
#
#   config_dir   ~/.config/palette-edge-libvirt        the projects
#   data_dir     ~/.local/share/palette-edge-libvirt   seeds and build files
#   cache_dir    ~/.cache/palette-edge-libvirt         the cloud image
#
# The API key sits beside the projects, but api_key_file computes its path on
# its own. See the comment there.
#
# The justfile computes the same three paths and exports them as PEL_CONFIG_DIR,
# PEL_DATA_DIR, and PEL_CACHE_DIR. A script that a recipe calls therefore takes
# the value of the recipe. A script that you call directly computes it again
# from the XDG variables. Set the PEL_ variable to move a directory.
config_dir() {
	printf '%s\n' "${PEL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/palette-edge-libvirt}"
}

data_dir() {
	printf '%s\n' "${PEL_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/palette-edge-libvirt}"
}

cache_dir() {
	printf '%s\n' "${PEL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/palette-edge-libvirt}"
}
# ANCHOR_END: dirs

# envs_dir: print the directory that holds one environment file for each
# project. The files hold registration tokens, so the directory is mode 0700.
envs_dir() {
	printf '%s/envs\n' "$(config_dir)"
}

# env_link: print the path of the link that selects the default project.
# It points at envs/<project>.env.
env_link() {
	printf '%s/env\n' "$(config_dir)"
}

# env_pointer: print the path of the .env file in the checkout.
#
# `set dotenv-path` in the justfile reads this path, and `just` accepts a
# constant only. It cannot name a directory in your home directory. The file is
# therefore a link to env_link, and it holds no value of its own.
env_pointer() {
	printf '%s/.env\n' "$(repo_root)"
}

# api_key_file: print the path of the Palette API key file.
#
# The key lives outside the checkout on purpose. It is a tenant credential, so
# no project recipe may delete it, and `just nuke` must not reach it.
#
# This path ignores PEL_CONFIG_DIR. A person can point that variable at a
# checkout, and a tenant credential must never go into one.
api_key_file() {
	printf '%s/palette-edge-libvirt/api-key\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# short_path: print a path with the home directory as a tilde.
short_path() {
	case "$1" in
	"$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
	*) printf '%s\n' "$1" ;;
	esac
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
