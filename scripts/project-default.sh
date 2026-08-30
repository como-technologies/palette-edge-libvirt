#!/usr/bin/env bash
# Select the project that every recipe operates on.
#
# One link holds the choice, and it is outside the checkout:
#
#   ~/.config/palette-edge-libvirt/env  ->  envs/<name>.env
#
# `scripts/dotenv.sh` reads that link, and `set dotenv-command` in the justfile
# reads that script. Every checkout of this repository therefore operates on
# the same project.
#
# This script is idempotent. A link that already points at the file stays.
#
#   project-default.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?give a project name}"
envs="$(envs_dir)"
link="$(env_link)"
target="envs/$name.env"

[ -f "$envs/$name.env" ] || die "$(short_path "$envs/$name.env") is absent.
     To see the projects that have a file: just projects
     To make one: just new-project $name"

if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
	skip "$name is already the default project"
	exit 0
fi

# A link that is relative to the configuration directory keeps that directory
# movable.
mkdir -p "$(dirname "$link")"
ln -sfn "$target" "$link"
info "the default project is now $name"
