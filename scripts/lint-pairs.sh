#!/usr/bin/env bash
# Test project rule 2: every recipe that creates an object has a recipe that
# removes it.
#
# This script is the single record of the pairs. The documentation includes the
# list below, so the book cannot disagree with the repository. `just lint` runs
# this script, so a rename or a new recipe that breaks a pair stops the build.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ANCHOR: pairs
# Each line is "create recipe" and "remove recipe".
PAIRS=(
	"host-setup          host-setup-undo"
	"net-up              net-down"
	"pool-up             pool-down"
	"infra-up            infra-down"
	"image-fetch         image-clean"
	"seed                seed-clean"
	"host-up             host-down"
	"cluster-up          cluster-down"
	"new-project         remove-project"
	"adopt-project       unadopt-project"
	"docs                docs-clean"
	"docs-theme          docs-theme-clean"
	"bash-completion-install bash-completion-uninstall"
)
# ANCHOR_END: pairs

# A recipe with one of these shapes creates something. It must appear as a
# create recipe in PAIRS. This test finds a new recipe that has no twin.
#
# The pattern starts with a hyphen, so every grep that uses it needs the --
# separator. Without it, grep reads the pattern as options and the test always
# passes.
CREATE_PATTERNS='-up$|-fetch$|-install$|^new-|^adopt-|-setup$'

cd "$(repo_root)"
need just

mapfile -t recipes < <(just --summary | tr ' ' '\n' | grep -v '^$' | sort -u)

has_recipe() {
	printf '%s\n' "${recipes[@]}" | grep -qx -- "$1"
}

fail=0

# 1. Both halves of each declared pair must exist.
creates=()
for pair in "${PAIRS[@]}"; do
	read -r create remove <<<"$pair"
	creates+=("$create")
	for name in "$create" "$remove"; do
		if ! has_recipe "$name"; then
			printf '  FAIL  the pair "%s / %s" names %s, and that recipe is absent\n' \
				"$create" "$remove" "$name"
			fail=1
		fi
	done
done

# 2. Each recipe that looks like a create recipe must be in the list.
while read -r name; do
	printf '%s\n' "${creates[@]}" | grep -qx -- "$name" && continue
	printf '  FAIL  recipe "%s" creates something and has no pair.\n' "$name"
	printf '        Add the remove recipe, then add both to PAIRS in %s\n' \
		"scripts/lint-pairs.sh"
	fail=1
done < <(printf '%s\n' "${recipes[@]}" | grep -E -- "$CREATE_PATTERNS" || true)

if [ "$fail" -eq 0 ]; then
	info "rule 2: ${#PAIRS[@]} create and remove pairs are complete"
fi

exit "$fail"
