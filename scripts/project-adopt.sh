#!/usr/bin/env bash
# Move an existing regular .env file into envs/, then link .env to it.
#
# Use this one time, when you already have a .env file and you want the
# project layout. `project-unadopt.sh` is the twin: it makes .env a regular
# file again.
#
# This script is idempotent. A .env that is already a link gives a skip.
#
#   project-adopt.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?give a project name}"
root="$(repo_root)"
link="$root/.env"
target="$root/envs/$name.env"

if [ -L "$link" ]; then
	skip ".env is already a link to $(readlink "$link")"
	exit 0
fi

[ -f "$link" ] || die ".env is absent. To make a project: just new-project $name"
[ ! -e "$target" ] || die "envs/$name.env already exists. Choose another name."

mkdir -p "$root/envs"
chmod 700 "$root/envs"
mv "$link" "$target"
chmod 600 "$target"
ln -sfn "envs/$name.env" "$link"

info "adopted the old .env as envs/$name.env"
info ".env -> envs/$name.env"
