#!/usr/bin/env bash
# Keep the Palette API key in one file, outside the repository.
#
# The API key is a tenant credential. It is not a project credential, and it is
# not scoped: a key carries every permission of the user that owns it. An
# earlier version of this repository wrote a copy into each project
# environment file, and `just remove-project` then deleted the key with the
# project. One project removal destroyed a tenant credential.
#
# The key now lives in one file that no project recipe touches.
#
#   api-key.sh set       read the key and write the file
#   api-key.sh status    report the length only, never the value
#   api-key.sh clear     delete the file
#
# To give the key for one command instead, set it in the environment:
#
#   PALETTE_API_KEY=... just palette-projects

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

action="${1:-status}"
file="$(api_key_file)"

case "$action" in
set)
	mkdir -p "$(dirname "$file")"
	chmod 700 "$(dirname "$file")"

	# The environment wins, so a script can set the key without a terminal.
	key="${PALETTE_API_KEY:-}"
	if [ -z "$key" ]; then
		[ -t 0 ] || die "there is no terminal to read the key.
     Give it in the environment instead:
       PALETTE_API_KEY=... just api-key-set"
		# -s stops the terminal from showing the key.
		printf 'Palette API key (Palette > User Menu > My API Keys): '
		read -rs key
		printf '\n'
	fi

	[ -n "$key" ] || die "the key is empty. Nothing was written."

	# Write with the mode already set, so the key is never world readable.
	install -m 600 /dev/null "$file"
	printf '%s\n' "$key" >"$file"
	info "wrote the key to $file (${#key} characters)"
	;;
status)
	if [ -s "$file" ]; then
		key="$(cat "$file")"
		info "the key file holds a key of ${#key} characters"
		printf '  %s\n' "$file"
	elif [ -n "${PALETTE_API_KEY:-}" ]; then
		info "there is no key file. The environment holds a key of ${#PALETTE_API_KEY} characters."
	else
		skip "there is no API key. Run: just api-key-set"
	fi
	;;
clear)
	if [ -f "$file" ]; then
		rm -f "$file"
		info "removed $file"
	else
		skip "there is no key file at $file"
	fi
	;;
*)
	die "unknown action '$action'. Use set, status, or clear."
	;;
esac
