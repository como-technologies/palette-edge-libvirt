#!/usr/bin/env bash
# Move a regular .env file from the checkout into the project layout.
#
# Use this one time, when you wrote a .env file by hand and you want the
# project layout. The script gives the file a project name, moves it to
# ~/.config/palette-edge-libvirt/envs/<name>.env, and makes that project the
# default. `project-unadopt.sh` is the twin.
#
# This script is idempotent. A .env that is already a link gives a skip.
#
#   project-adopt.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?give a project name}"
here="$(dirname "${BASH_SOURCE[0]}")"
pointer="$(env_pointer)"
envs="$(envs_dir)"
target="$envs/$name.env"

if [ -L "$pointer" ]; then
	skip ".env is already a link to $(short_path "$(readlink "$pointer")")"
	exit 0
fi

[ -f "$pointer" ] || die ".env is absent. To make a project: just new-project $name"
[ ! -e "$target" ] || die "$(short_path "$target") already exists. Choose another name."

mkdir -p "$envs"
chmod 700 "$envs"
mv "$pointer" "$target"
chmod 600 "$target"

info "adopted the old .env as $(short_path "$target")"

"$here/project-default.sh" "$name"
