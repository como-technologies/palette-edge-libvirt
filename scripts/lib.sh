#!/usr/bin/env bash
# Shared functions for the scripts of this repository. Source this file.
# Do not execute it.

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
# The recipes are idempotent. A second run reports a skip and returns 0.
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
# The tooling directories.
#
# The checkout holds the source only. Every file that you want to keep lives in
# one of four directories outside it, so `rm -rf` on the checkout destroys no
# project, no token, no state file, and no download.
#
#   config_dir   ~/.config/palette-edge-libvirt        the projects
#   data_dir     ~/.local/share/palette-edge-libvirt   seeds and build files
#   state_dir    ~/.local/state/palette-edge-libvirt   the OpenTofu state
#   cache_dir    ~/.cache/palette-edge-libvirt         the cloud image
#
# The API key sits beside the projects, but api_key_file computes its path on
# its own. See the comment there.
#
# The justfile computes the same four paths and exports them as PEL_CONFIG_DIR,
# PEL_DATA_DIR, PEL_STATE_DIR, and PEL_CACHE_DIR. A script that a recipe calls
# therefore takes the value of the recipe. A script that you call directly
# computes it again from the XDG variables. Set the PEL_ variable to move a
# directory.
config_dir() {
	printf '%s\n' "${PEL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/palette-edge-libvirt}"
}

data_dir() {
	printf '%s\n' "${PEL_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/palette-edge-libvirt}"
}

state_dir() {
	printf '%s\n' "${PEL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/palette-edge-libvirt}"
}

cache_dir() {
	printf '%s\n' "${PEL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/palette-edge-libvirt}"
}
# ANCHOR_END: dirs

# ANCHOR: projectstate
# project_state_dir: print the directory that holds the OpenTofu state of one
# Palette project.
#
# The state names the cluster profile and the cluster that OpenTofu made, so
# one project gets one directory. A second project therefore builds its own
# cluster, and neither one can destroy the objects of the other.
#
# The state is not a cache. It is the only record that connects the objects in
# Palette to this checkout, so it lives in the XDG state directory and never in
# the checkout, never in the module, and never in the current directory.
project_state_dir() {
	need_project
	printf '%s/%s\n' "$(state_dir)" "$PALETTE_PROJECT"
}
# ANCHOR_END: projectstate

# bin_dir: print the directory that holds the tools this tooling installs for
# your user. The directory needs no root, and it is usually already on PATH.
bin_dir() {
	printf '%s\n' "${PEL_BIN_DIR:-$HOME/.local/bin}"
}

# envs_dir: print the directory that holds one environment file for each
# project. The files hold registration tokens, so the directory is mode 0700.
envs_dir() {
	printf '%s/envs\n' "$(config_dir)"
}

# env_link: print the path of the link that selects the default project.
#
# The link points at envs/<project>.env. `scripts/dotenv.sh` reads it, and the
# justfile reads that script. The link is the only record of the choice, and it
# is outside the checkout, so two checkouts of this repository operate on the
# same project.
env_link() {
	printf '%s/env\n' "$(config_dir)"
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

# domains_using_network: print the name of each domain attached to a network.
#
# libvirt removes a network that a running domain uses, and it reports no error
# when it does. The domain keeps running with a bridge that is gone: it never
# gets an address, so it never registers, and nothing says why. The recipes
# therefore test this before they remove a network.
#
# Every domain, not the running ones alone. A domain that is off holds the same
# reference, and it fails at the next start.
domains_using_network() {
	local network="$1" domain
	while read -r domain; do
		[ -n "$domain" ] || continue
		if virsh domiflist "$domain" 2>/dev/null |
			awk -v n="$network" '$2 == "network" && $3 == n { found = 1 }
			     END { exit !found }'; then
			printf '%s\n' "$domain"
		fi
	done < <(virsh list --all --name 2>/dev/null)
}

# domains_using_pool: print the name of each domain with a file in a directory.
#
# The same reason as domains_using_network. A pool that goes while a domain
# holds a disk in it leaves the disk with no record of where it belongs, and
# host-down.sh then cannot tell a pool file from one of yours.
domains_using_pool() {
	local target="$1" domain
	[ -n "$target" ] || return 0
	while read -r domain; do
		[ -n "$domain" ] || continue
		if virsh domblklist "$domain" --details 2>/dev/null |
			awk -v p="$target/" '$1 == "file" && index($4, p) == 1 { found = 1 }
			     END { exit !found }'; then
			printf '%s\n' "$domain"
		fi
	done < <(virsh list --all --name 2>/dev/null)
}
