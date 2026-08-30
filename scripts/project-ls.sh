#!/usr/bin/env bash
# List the projects that have an environment file, and mark the default.
#
# This script reads the local files only. It makes no API call, so it needs no
# API key. To read the tenant, run `just palette-projects`.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

envs="$(envs_dir)"
link="$(env_link)"

current=""
if [ -L "$link" ]; then
	current="$(basename "$(readlink "$link")" .env)"
fi

shopt -s nullglob
files=("$envs"/*.env)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
	skip "there are no environment files. Make one with: just new-project <name>"
	exit 0
fi

printf '%-3s %-24s %-12s %s\n' "" PROJECT CLUSTER SUBNET
for file in "${files[@]}"; do
	project="$(basename "$file" .env)"
	# `|| true` on each. grep reports "no match" as a failure, `set -o
	# pipefail` makes that the value of the pipeline, and `set -e` then ends
	# this script with no output at all. A file that holds neither name is
	# exactly the file that this table needs to show, so it prints a dash.
	cluster="$(grep -sE '^CLUSTER_NAME=' "$file" | cut -d= -f2 || true)"
	subnet="$(grep -sE '^CLUSTER_SUBNET=' "$file" | cut -d= -f2 || true)"
	mark=" "
	[ "$project" = "$current" ] && mark="*"
	printf ' %-2s %-24s %-12s %s.0/24\n' "$mark" "$project" "${cluster:--}" "${subnet:--}"
done

echo
info "the files are in $(short_path "$envs")"

if [ -z "$current" ]; then
	warn "there is no default project, so every recipe uses its default value.
         Choose one: just default-project <name>"
	exit 0
fi

info "* is the default project"
