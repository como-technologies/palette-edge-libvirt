#!/usr/bin/env bash
# Move the lab files out of the checkout into the XDG directories.
#
# An early version of this repository kept the projects, the seeds, the build
# files, and the cloud image in the checkout. `rm -rf` on the checkout then
# destroyed the projects and their registration tokens.
#
# This script moves each of those directories to its correct place:
#
#   envs/    ->  ~/.config/palette-edge-libvirt/envs
#   seeds/   ->  ~/.local/share/palette-edge-libvirt/seeds
#   build/   ->  ~/.local/share/palette-edge-libvirt/build
#   images/  ->  ~/.cache/palette-edge-libvirt/images
#
# It then makes .env a link to ~/.config/palette-edge-libvirt/env. The justfile
# reads .env, and that file is the only lab file that stays in the checkout.
#
# The script moves no file that the destination already holds. It reports each
# of those and keeps the copy in the checkout, so no version is lost.
#
# This script is idempotent. A checkout that holds none of these directories
# gives a skip. `xdg-unadopt.sh` is the twin.
#
#   xdg-adopt.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root="$(repo_root)"
moved=0

# move_dir SRC DST MODE: move the content of one directory to another.
#
# The script moves the files, not the directory, so a destination that already
# holds files keeps them. A name that exists at both ends stays in the checkout
# and gets a warning.
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
			warn "$(short_path "$dst/$base") already exists. $src/$base stays."
			kept=$((kept + 1))
			continue
		fi
		mv "$file" "$dst/$base"
		count=$((count + 1))
	done

	if [ "$count" -gt 0 ]; then
		info "moved $count file(s) from ${src#"$root"/} to $(short_path "$dst")"
		moved=$((moved + count))
	fi

	# Remove the old directory only when it is empty. A kept file holds it.
	if [ "$kept" -eq 0 ]; then
		rmdir "$src" 2>/dev/null || true
	fi
	return 0
}

# --- 1. remember the default project ----------------------------------------

# .env may still be a link to envs/<name>.env in the checkout. Read the name
# before the move, so the same project stays the default after it.
pointer="$(env_pointer)"
current=""
if [ -L "$pointer" ]; then
	target="$(readlink "$pointer")"
	case "$target" in
	envs/*.env) current="$(basename "$target" .env)" ;;
	esac
fi

# --- 2. the directories -----------------------------------------------------

move_dir "$root/envs" "$(envs_dir)" 700
move_dir "$root/seeds" "$(data_dir)/seeds" 700
move_dir "$root/build" "$(data_dir)/build" 755
move_dir "$root/images" "$(cache_dir)/images" 755

# The environment files hold registration tokens.
shopt -s nullglob
for file in "$(envs_dir)"/*.env; do chmod 600 "$file"; done
shopt -u nullglob

# --- 3. the .env link -------------------------------------------------------

if [ -e "$pointer" ] && [ ! -L "$pointer" ]; then
	warn ".env is a regular file, so this script did not touch it.
         It works where it is. To give it a project name and move it:
           just adopt-project <name>"
elif [ -n "$current" ]; then
	"$(dirname "${BASH_SOURCE[0]}")/project-default.sh" "$current"
elif [ -L "$pointer" ] && [ "$(readlink "$pointer")" = "$(env_link)" ]; then
	skip ".env already points at $(short_path "$(env_link)")"
elif [ -L "$pointer" ]; then
	rm -f "$pointer"
	warn "the old .env pointed at $(short_path "$target"), and that is not a
         project file. Choose a project: just default-project <name>"
fi

if [ "$moved" -eq 0 ]; then
	skip "the checkout holds no lab files. There is nothing to move."
else
	info "the checkout holds source only now. Run: just config"
fi
