#!/usr/bin/env bash
# List the projects that have an environment file, and mark the default.
#
# This script reads the local files only. It makes no API call, so it needs no
# API key. To read the tenant, run `just palette-projects`.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root="$(repo_root)"
envs="$root/envs"
link="$root/.env"

current=""
if [ -L "$link" ]; then
	current="$(basename "$(readlink "$link")" .env)"
fi

shopt -s nullglob
files=("$envs"/*.env)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
	skip "there are no environment files. Make one with: just new-project <name>"
	if [ -e "$link" ] && [ ! -L "$link" ]; then
		info ".env is a regular file, so the lab uses it directly."
	fi
	exit 0
fi

printf '%-3s %-24s %-10s %s\n' "" PROJECT LAB SUBNET
for file in "${files[@]}"; do
	project="$(basename "$file" .env)"
	lab="$(grep -sE '^LAB_NAME=' "$file" | cut -d= -f2)"
	subnet="$(grep -sE '^LAB_SUBNET=' "$file" | cut -d= -f2)"
	mark=" "
	[ "$project" = "$current" ] && mark="*"
	printf ' %-2s %-24s %-10s %s.0/24\n' "$mark" "$project" "${lab:--}" "${subnet:--}"
done

echo
if [ -n "$current" ]; then
	info "* is the default project. .env -> envs/$current.env"
else
	warn "there is no default project. Choose one: just default-project <name>"
fi
