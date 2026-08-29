#!/usr/bin/env bash
# Point the .env symbolic link at the environment file of one project.
#
# `set dotenv-load` in the justfile reads .env. The link therefore selects the
# project that every recipe operates on.
#
# This script is idempotent. A link that already points at the file stays.
#
#   project-default.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?give a project name}"
root="$(repo_root)"
target="envs/$name.env"
link="$root/.env"

[ -f "$root/$target" ] || die "envs/$name.env is absent.
     To see the projects that have a file: just projects
     To make one: just new-project $name"

# A regular .env file is a file that a person wrote by hand. Do not delete it
# without a word, because it holds the token.
if [ -e "$link" ] && [ ! -L "$link" ]; then
	backup="$root/.env.bak.$(date +%s)"
	mv "$link" "$backup"
	warn "the old .env was a regular file. It is now $(basename "$backup")."
	warn "Git ignores that name. Delete it when you no longer need it."
fi

if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
	skip "$name is already the default project"
	exit 0
fi

# A relative link keeps the checkout movable.
ln -sfn "$target" "$link"
info "the default project is now $name (.env -> $target)"
