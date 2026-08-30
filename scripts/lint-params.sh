#!/usr/bin/env bash
# Test that the bash completion covers every recipe parameter.
#
# The completion reads the recipes from `just`, so it needs no list of recipe
# names. It does need to know each kind of value. A parameter takes its name
# from the kind of value it holds, for example `host` or `project`.
#
# This test reads the kinds from the generated completion and the parameters
# from `just`. A new parameter with an unknown name stops the build, which is
# the moment to add the kind or to name the parameter as free text.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$(repo_root)"
need just
need python3

completion="$(scripts/bash-completion.sh print)"

# Read the two lists from the completion. The completion is the one record of
# them, so this test cannot disagree with it.
kinds="$(printf '%s\n' "$completion" | sed -n 's/^_PEL_KINDS="\(.*\)"$/\1/p')"
free="$(printf '%s\n' "$completion" | sed -n 's/^_PEL_KINDS_FREE="\(.*\)"$/\1/p')"

[ -n "$kinds" ] || die "cannot read _PEL_KINDS from the completion"

known=" $kinds $free "
fail=0

while read -r recipe param; do
	case "$known" in
	*" $param "*) ;;
	*)
		printf '  FAIL  recipe "%s" has the parameter "%s", and the completion\n' \
			"$recipe" "$param"
		printf '        does not know that name.\n'
		printf '        Name the parameter for the kind of value it holds, or add\n'
		printf '        the kind to _PEL_KINDS in scripts/bash-completion.sh.\n'
		fail=1
		;;
	esac
done < <(
	just --dump --dump-format json | python3 -c '
import json, sys
data = json.load(sys.stdin)
for name, recipe in sorted((data.get("recipes") or {}).items()):
    for param in recipe.get("parameters") or []:
        print(name, param["name"])
'
)

if [ "$fail" -eq 0 ]; then
	info "completion: every recipe parameter has a known kind ($kinds)"
fi

exit "$fail"
