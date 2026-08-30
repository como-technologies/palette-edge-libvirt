#!/usr/bin/env bash
# Remove a Palette project and its environment file.
#
# This is the twin of project-new.sh. It reverses all three of its steps.
#
# The script deletes an object in your tenant, and that is not reversible. It
# therefore asks for the project name before it deletes. Give FORCE=1 to answer
# in advance.
#
# The script refuses while the project holds a host or a cluster. Remove the
# cluster first with `just cluster-down`, then deregister the hosts in Palette.
#
# This script is idempotent. An absent project or an absent file gives a skip.
#
#   project-remove.sh <name>
#   FORCE=1 project-remove.sh <name>

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

name="${1:?give a project name}"
target="$(envs_dir)/$name.env"
link="$(env_link)"

need curl
need python3

# Resolve the API key before any pipeline runs. die() inside a pipeline stops
# only the subshell, and the reader then fails on empty input.
need_api_key

uid="$(project_uid "$name" || true)"

if [ -z "$uid" ]; then
	skip "project $name is absent from the tenant"
else
	# Count what the project holds. A delete with content leaves orphans in
	# Palette, and those are slow to find later.
	hosts="$(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid" |
		python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("items") or []))')"
	clusters="$(api GET "v1/spectroclusters?limit=100" -H "ProjectUid: $uid" |
		python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("items") or []))' 2>/dev/null || echo 0)"

	if [ "$hosts" -gt 0 ] || [ "$clusters" -gt 0 ]; then
		die "project $name still holds $clusters cluster(s) and $hosts host(s).
     Remove the cluster layer, then the machines and their records:
       just cluster-down
       just palette-hosts                  # the names
       just host-deregister <host>         # one for each name
     Then run this recipe again."
	fi

	# Palette refuses to delete a project while a registration token names it
	# as its default project. Find that token now, so the question can name
	# everything that this recipe deletes.
	token_uid="$(token_for_project "$uid" || true)"
	token_label=""
	if [ -n "$token_uid" ]; then
		token_label="$(token_name "$token_uid" || true)"
	fi

	if [ "${FORCE:-0}" != "1" ]; then
		printf 'This deletes the Palette project %s (%s) from your tenant.\n' "$name" "$uid"
		if [ -n "$token_uid" ]; then
			printf 'It also deletes the registration token %s, because Palette\n' \
				"${token_label:-$token_uid}"
			printf 'keeps the project while a token names it.\n'
		fi
		printf 'This action is not reversible.\n'
		printf 'Type the project name to continue: '
		read -r answer
		[ "$answer" = "$name" ] || die "the answer did not match. Nothing changed."
	fi

	# The token goes first. The project delete fails while the token exists.
	if [ -n "$token_uid" ]; then
		api DELETE "v1/edgehosts/tokens/$token_uid" >/dev/null
		info "deleted the registration token ${token_label:-$token_uid}"
	fi

	api DELETE "v1/projects/$uid" >/dev/null
	info "deleted the project $name from the tenant"
fi

# The environment file holds the token, so remove it with the project.
if [ -f "$target" ]; then
	rm -f "$target"
	info "removed $(short_path "$target")"
else
	skip "$(short_path "$target") is absent"
fi

# A link to the removed file would break every recipe. Remove it and name the
# next step.
if [ -L "$link" ] && [ "$(readlink "$link")" = "envs/$name.env" ]; then
	rm -f "$link"
	warn "$name was the default project. There is no default now."
	warn "Choose one with: just default-project <name>"
fi
