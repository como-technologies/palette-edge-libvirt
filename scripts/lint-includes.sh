#!/usr/bin/env bash
# Test project rule 5: the documentation includes the source.
#
# mdBook fails the build when an include names a file that is absent. It does
# NOT fail when the file exists and the anchor is absent: it writes an empty
# code block and reports nothing. A renamed anchor therefore removes an example
# from the book, and no test notices.
#
# This script reads every include in docs/src and tests both halves.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$(repo_root)"

fail=0
count=0

# grep gives "docs/src/page.md:<the whole line>" for each one. The anchor is
# optional, and an include with no anchor takes the whole file.
while IFS= read -r line; do
	doc="${line%%:*}"
	text="${line#*:}"

	# rules.md shows the syntax as an example, and escapes it with a
	# backslash so that mdBook prints it. Do not test an example.
	case "$text" in
	*'\{{#include'*) continue ;;
	esac

	spec="${text#*\{\{#include }"
	spec="${spec%%\}\}*}"

	target="${spec%%:*}"
	anchor=""
	case "$spec" in
	*:*) anchor="${spec#*:}" ;;
	esac

	# The path in an include is relative to the file that holds it.
	path="$(cd "$(dirname "$doc")" && realpath -m "$target")"
	count=$((count + 1))

	if [ ! -f "$path" ]; then
		printf '  FAIL  %s includes %s, and that file is absent\n' "$doc" "$target"
		fail=1
		continue
	fi

	[ -n "$anchor" ] || continue

	if ! grep -qE "ANCHOR:[[:space:]]*${anchor}([[:space:]]|\$)" "$path"; then
		printf '  FAIL  %s includes %s:%s, and that anchor is absent.\n' \
			"$doc" "$target" "$anchor"
		printf '        mdBook writes an empty code block and reports nothing.\n'
		fail=1
		continue
	fi

	if ! grep -qE "ANCHOR_END:[[:space:]]*${anchor}([[:space:]]|\$)" "$path"; then
		printf '  FAIL  %s includes %s:%s, and ANCHOR_END is absent\n' \
			"$doc" "$target" "$anchor"
		fail=1
	fi
done < <(grep -rH '{{#include' docs/src/*.md || true)

if [ "$fail" -eq 0 ]; then
	info "rule 5: $count include(s) name a file and an anchor that exist"
fi

exit "$fail"
