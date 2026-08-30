#!/usr/bin/env bash
# Create a Palette project and its environment file, then make it the default.
#
# The script does three things:
#   1. It creates the project in your Palette tenant.
#   2. It creates a registration token that belongs to that project.
#   3. It writes the environment file of the project with that token.
#   4. It makes that project the default.
#
# The environment file goes to ~/.config/palette-edge-libvirt/envs/<name>.env.
# It is outside the checkout, so `rm -rf` on the checkout keeps it.
#
# The lab keeps one environment file for each project. A different LAB_NAME and
# a different LAB_SUBNET for each project let two labs run at the same time.
#
# This script is idempotent. An existing project or an existing file stays as
# it is, and the script only points the link.
#
#   project-new.sh <name> [description]

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

name="${1:?give a project name}"
description="${2:-}"
root="$(repo_root)"
envs="$(envs_dir)"
target="$envs/$name.env"

need curl
need python3

# Resolve the API key before any pipeline runs. die() inside a pipeline stops
# only the subshell, and the reader then fails on empty input.
need_api_key

# Palette project names permit letters, numbers, and the hyphen. Stop early
# with a clear message instead of an API error.
if ! printf '%s' "$name" | grep -qE '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$'; then
	die "'$name' is not a valid project name.
     Use lower case letters, numbers, and the hyphen. Start and end with a
     letter or a number. Use 3 to 63 characters."
fi

[ -n "$description" ] ||
	description="Palette Edge lab on $(hostname --short). Managed by palette-edge-libvirt."

mkdir -p "$envs"
chmod 700 "$envs"

# --- 1. the Palette project -------------------------------------------------

uid="$(project_uid "$name" || true)"
if [ -n "$uid" ]; then
	skip "project $name already exists ($uid)"
else
	info "create the project $name"
	body="$(NAME="$name" DESC="$description" python3 -c '
import json, os
print(json.dumps({
    "metadata": {
        "name": os.environ["NAME"],
        # Palette keeps the description in an annotation, not in a field.
        "annotations": {"description": os.environ["DESC"]},
        "labels": {"managedBy": "palette-edge-libvirt"},
    }
}))
')"
	api POST "v1/projects" -H "Content-Type: application/json" -d "$body" >/dev/null
	uid="$(project_uid "$name" || true)"
	[ -n "$uid" ] || die "the project was created but does not appear in the list"
	info "created $name ($uid)"
fi

# --- 2. the registration token ----------------------------------------------

# Each project gets its own token. The token registers a host into that project
# only, and `remove-project` deletes it with the project. This also removes the
# one manual step that remained: nobody has to copy a token from the console.

token_uid="$(token_for_project "$uid" || true)"
if [ -n "$token_uid" ]; then
	skip "the project already has a registration token"
else
	info "create the registration token $name"
	token_uid="$(token_create "$name" "$description" "$uid" "${PALETTE_TOKEN_DAYS:-90}")"
	[ -n "$token_uid" ] || die "the token was created but the API returned no uid"
	info "created the token (expires in ${PALETTE_TOKEN_DAYS:-90} days)"
fi

# Never print this value.
token="$(token_value "$token_uid")"
[ -n "$token" ] || warn "the API returned no token value. Add PALETTE_EDGE_TOKEN by hand."

# --- 3. the environment file ------------------------------------------------

if [ -f "$target" ]; then
	skip "$(short_path "$target") already exists"
else
	# lab_name: a short prefix for the libvirt objects. It must be unique, so
	# every object of two labs stays separate.
	#
	# The limit of 12 characters comes from the bridge name. A Linux interface
	# name takes 15 characters, and the bridge is "br-" and the lab name.
	lab_name="$(printf '%s' "$name" | tr -cd 'a-z0-9' | cut -c1-12)"
	[ -n "$lab_name" ] || lab_name="lab"
	suffix=""
	while grep -qsE "^LAB_NAME=${lab_name}${suffix}$" "$envs"/*.env 2>/dev/null; do
		suffix=$((${suffix:-1} + 1))
	done
	lab_name="${lab_name}${suffix}"

	# lab_subnet: the first free 192.168.N.0/24. The script reads the subnets
	# of the other environment files and of the libvirt networks, so a new
	# project never collides with a running lab.
	used="$(
		{
			grep -hsE '^LAB_SUBNET=' "$envs"/*.env 2>/dev/null | cut -d= -f2
			if command -v virsh >/dev/null 2>&1; then
				for net in $(virsh net-list --all --name 2>/dev/null); do
					virsh net-dumpxml "$net" 2>/dev/null |
						sed -n "s/.*<ip address='\([0-9.]*\)\.[0-9]*'.*/\1/p"
				done
			fi
		} | sort -u
	)"
	lab_subnet=""
	for n in $(seq 140 199); do
		if ! printf '%s\n' "$used" | grep -qx "192.168.$n"; then
			lab_subnet="192.168.$n"
			break
		fi
	done
	[ -n "$lab_subnet" ] || die "no free subnet between 192.168.140 and 192.168.199"

	info "write $(short_path "$target") (lab $lab_name, subnet $lab_subnet.0/24)"

	NAME="$name" LAB="$lab_name" SUBNET="$lab_subnet" \
		SRC="$root/.env.example" DST="$target" \
		ENDPOINT="$(palette_endpoint)" NEW_TOKEN="$token" \
		python3 -c '
import os, re, sys

subs = {
    "PALETTE_ENDPOINT": os.environ["ENDPOINT"],
    "PALETTE_PROJECT": os.environ["NAME"],
    "PALETTE_EDGE_TOKEN": os.environ.get("NEW_TOKEN", ""),
    "LAB_NAME": os.environ["LAB"],
    "LAB_SUBNET": os.environ["SUBNET"],
}
out = []
for line in open(os.environ["SRC"]):
    m = re.match(r"^([A-Z_]+)=", line)
    if m and m.group(1) in subs:
        out.append("{}={}\n".format(m.group(1), subs[m.group(1)]))
    else:
        out.append(line)
open(os.environ["DST"], "w").write("".join(out))
'
	chmod 600 "$target"
fi

# --- 4. the default ---------------------------------------------------------

"$(dirname "${BASH_SOURCE[0]}")/project-default.sh" "$name"

if ! grep -qE '^PALETTE_EDGE_TOKEN=.+$' "$target"; then
	warn "PALETTE_EDGE_TOKEN is empty in $(short_path "$target"). Add it before you run
         just cluster-up."
fi
