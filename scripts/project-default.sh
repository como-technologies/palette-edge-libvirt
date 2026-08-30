#!/usr/bin/env bash
# Select the project that every recipe operates on.
#
# Two links do this:
#
#   ~/.config/palette-edge-libvirt/env  ->  envs/<name>.env
#   <checkout>/.env                     ->  ~/.config/palette-edge-libvirt/env
#
# The first link holds the choice, and it lives outside the checkout. The
# second link is a fixed pointer, because `set dotenv-path` in the justfile
# takes a constant and cannot name your home directory.
#
# This script is idempotent. Links that already point at the file stay.
#
#   project-default.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?give a project name}"
envs="$(envs_dir)"
link="$(env_link)"
pointer="$(env_pointer)"
target="envs/$name.env"

[ -f "$envs/$name.env" ] || die "$(short_path "$envs/$name.env") is absent.
     To see the projects that have a file: just projects
     To make one: just new-project $name"

changed=0

# --- 1. the choice ----------------------------------------------------------

if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
	skip "$name is already the default project"
else
	# A link that is relative to the configuration directory keeps that
	# directory movable.
	mkdir -p "$(dirname "$link")"
	ln -sfn "$target" "$link"
	info "the default project is now $name"
	changed=1
fi

# --- 2. the pointer in the checkout -----------------------------------------

# A regular .env file is a file that a person wrote by hand. Do not delete it
# without a word, because it holds the token.
if [ -e "$pointer" ] && [ ! -L "$pointer" ]; then
	backup="$pointer.bak.$(date +%s)"
	mv "$pointer" "$backup"
	warn "the old .env was a regular file. It is now $(basename "$backup")."
	warn "Git ignores that name. Delete it when you no longer need it."
fi

if [ -L "$pointer" ] && [ "$(readlink "$pointer")" = "$link" ]; then
	[ "$changed" -eq 1 ] || skip ".env already points at $(short_path "$link")"
else
	ln -sfn "$link" "$pointer"
	info ".env -> $(short_path "$link")"
fi
