#!/usr/bin/env bash
# Move the lab files from the XDG directories back into the checkout.
#
# This is the twin of xdg-adopt.sh. It reverses each move:
#
#   ~/.config/palette-edge-libvirt/envs       ->  envs/
#   ~/.local/share/palette-edge-libvirt/seeds ->  seeds/
#   ~/.local/share/palette-edge-libvirt/build ->  build/
#   ~/.cache/palette-edge-libvirt/images      ->  images/
#
# The recipes still read the XDG directories, so set PEL_CONFIG_DIR,
# PEL_DATA_DIR, and PEL_CACHE_DIR in your shell after this script. Without them
# the next recipe writes to the XDG directories again.
#
# The script keeps the API key. That key is a tenant credential, and the
# checkout is not a safe place for it.
#
# The script moves no file that the destination already holds.
#
# This script is idempotent. Empty XDG directories give a skip.
#
#   xdg-unadopt.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root="$(repo_root)"
moved=0

# move_dir SRC DST MODE: move the content of one directory to another.
# A name that exists at both ends stays where it is and gets a warning.
move_dir() {
	local src="$1" dst="$2" mode="$3" file base kept=0 count=0

	[ -d "$src" ] || return 0

	shopt -s nullglob dotglob
	local files=("$src"/*)
	shopt -u nullglob dotglob

	if [ "${#files[@]}" -eq 0 ]; then
		rmdir "$src" 2>/dev/null || true
		return 0
	fi

	mkdir -p "$dst"
	chmod "$mode" "$dst"

	for file in "${files[@]}"; do
		base="$(basename "$file")"
		if [ -e "$dst/$base" ]; then
			warn "${dst#"$root"/}/$base already exists. $(short_path "$src/$base") stays."
			kept=$((kept + 1))
			continue
		fi
		mv "$file" "$dst/$base"
		count=$((count + 1))
	done

	if [ "$count" -gt 0 ]; then
		info "moved $count file(s) from $(short_path "$src") to ${dst#"$root"/}"
		moved=$((moved + count))
	fi

	if [ "$kept" -eq 0 ]; then
		rmdir "$src" 2>/dev/null || true
	fi
	return 0
}

# --- 1. remember the default project ----------------------------------------

link="$(env_link)"
current=""
if [ -L "$link" ]; then
	current="$(basename "$(readlink "$link")" .env)"
fi

# --- 2. the directories -----------------------------------------------------

move_dir "$(envs_dir)" "$root/envs" 700
move_dir "$(data_dir)/seeds" "$root/seeds" 700
move_dir "$(data_dir)/build" "$root/build" 755
move_dir "$(cache_dir)/images" "$root/images" 755

shopt -s nullglob
for file in "$root"/envs/*.env; do chmod 600 "$file"; done
shopt -u nullglob

# --- 3. the .env link -------------------------------------------------------

# .env goes back to a relative link into the checkout, and the link in the
# config directory goes away.
pointer="$(env_pointer)"

if [ -e "$pointer" ] && [ ! -L "$pointer" ]; then
	skip ".env is a regular file. It stays as it is."
elif [ -n "$current" ] && [ -f "$root/envs/$current.env" ]; then
	ln -sfn "envs/$current.env" "$pointer"
	info ".env -> envs/$current.env"
elif [ -L "$pointer" ]; then
	rm -f "$pointer"
	warn "there is no default project now. Choose one: just default-project <name>"
fi

rm -f "$link"

# Remove the directories that this script emptied. The config directory stays,
# because it holds the API key.
rmdir "$(data_dir)" "$(cache_dir)" 2>/dev/null || true

if [ "$moved" -eq 0 ]; then
	skip "the XDG directories hold no lab files. There is nothing to move."
else
	warn "the recipes still read the XDG directories. Export these first:
           export PEL_CONFIG_DIR=$root
           export PEL_DATA_DIR=$root
           export PEL_CACHE_DIR=$root"
fi
