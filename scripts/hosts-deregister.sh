#!/usr/bin/env bash
# Remove the Palette record of every host of this cluster.
#
# A host record belongs to the infrastructure layer. Registration makes it, and
# the record has no use when the virtual machine is gone, so `just infra-down`
# calls this script before it removes the domains.
#
# Two values give the scope, and both come from the environment file of the
# default project:
#
#   PALETTE_PROJECT   the script reads the hosts of this project only
#   CLUSTER_NAME      the script keeps the names that start with this prefix
#
# A project holds one cluster, so the prefix normally keeps every host. The
# script names each host that the prefix does not keep, because a silent skip
# leaves a record that nothing removes.
#
# This script is idempotent. A cluster with no record gives a skip.
#
# Env: CLUSTER
#
#   hosts-deregister.sh

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

: "${CLUSTER:?}"
here="$(dirname "${BASH_SOURCE[0]}")"

need curl
need python3
need_api_key
need_project

uid="$(project_uid "$PALETTE_PROJECT")"
[ -n "$uid" ] || die "project $PALETTE_PROJECT does not exist in this tenant.
     To see the names: just palette-projects"

# Tag each host, so the script can name the ones that it does not touch.
mapfile -t rows < <(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid" |
	CLUSTER="$CLUSTER" python3 -c '
import json, os, sys
prefix = os.environ["CLUSTER"] + "-"
for host in json.load(sys.stdin).get("items") or []:
    name = host["metadata"]["name"]
    print("mine" if name.startswith(prefix) else "other", name)
')

hosts=()
others=()
for row in "${rows[@]}"; do
	case "$row" in
	"mine "*) hosts+=("${row#mine }") ;;
	"other "*) others+=("${row#other }") ;;
	esac
done

# CLUSTER_NAME gives the prefix. A host that registered under an earlier name
# keeps that name, and this script would leave it with no message.
if [ "${#others[@]}" -gt 0 ]; then
	warn "${#others[@]} host(s) of project $PALETTE_PROJECT do not start with ${CLUSTER}-:
         ${others[*]}
         This recipe left them. To remove one: just host-deregister <host>"
fi

if [ "${#hosts[@]}" -eq 0 ]; then
	skip "no ${CLUSTER}-* host has a record in project $PALETTE_PROJECT"
	exit 0
fi

info "remove ${#hosts[@]} Palette record(s): ${hosts[*]}"
for host in "${hosts[@]}"; do
	"$here/host-deregister.sh" "$host"
done
