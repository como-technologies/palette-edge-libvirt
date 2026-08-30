#!/usr/bin/env bash
# Wait until every host of this cluster registers with Palette.
#
# This script is the seam between the two layers. The infrastructure layer is
# complete when each host holds a record in Palette, because a virtual machine
# that did not register is of no use to the cluster layer. `just infra-up`
# therefore ends here, and `just cluster-up` starts from a registered host.
#
# A host boots, cloud-init installs the agent, and the host restarts one time.
# The whole sequence takes some minutes, so this script prints the state of
# each host while it waits.
#
# This script is idempotent. A cluster that already registered returns at once.
#
# Env: CLUSTER CONTROL_COUNT WORKER_COUNT REGISTER_TIMEOUT
#
#   hosts-wait.sh

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

: "${CLUSTER:?}"
timeout="${REGISTER_TIMEOUT:-900}"
interval=15

need curl
need python3
need_api_key
need_project

uid="$(project_uid "$PALETTE_PROJECT")"
[ -n "$uid" ] || die "project $PALETTE_PROJECT does not exist in this tenant.
     To see the names: just palette-projects"

# The names that the topology gives. host-up makes a domain for each one.
want=()
for i in $(seq 1 "${CONTROL_COUNT:-1}"); do want+=("${CLUSTER}-cp-$i"); done
for i in $(seq 1 "${WORKER_COUNT:-2}"); do want+=("${CLUSTER}-wk-$i"); done

# A machine that does not exist never registers. Without this test the script
# asks the API every 15 seconds for the whole timeout, 15 minutes by default,
# and then reports that the hosts did not register. The cause is visible now,
# and libvirt answers in a moment.
#
# A host that registered and then lost its machine is not a fault here: the
# record is what the cluster layer reads, and this script waits for the record.
# So a name passes if it has a domain OR it already holds a record.
if command -v virsh >/dev/null 2>&1; then
	body="$(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid")"
	registered="$(printf '%s' "$body" |
		python3 -c '
import json, sys
for host in json.load(sys.stdin).get("items") or []:
    print(host["metadata"]["name"])
' || true)"

	absent=()
	for name in "${want[@]}"; do
		have_domain "$name" && continue
		printf '%s\n' "$registered" | grep -qx "$name" && continue
		absent+=("$name")
	done

	if [ "${#absent[@]}" -gt 0 ]; then
		die "these host(s) have no virtual machine and no record in Palette:
       ${absent[*]}
     Nothing can register, so this recipe would wait ${timeout}s for no reason.
     To make the machines:       just infra-up
     To see the machines:        just ls"
	fi
fi

info "wait for ${#want[@]} host(s) to register in project $PALETTE_PROJECT"
info "a host boots, installs the agent, and restarts one time. Give it minutes."

start="$(date +%s)"

while :; do
	# Read the name and the state of each registered host one time for each
	# turn of the loop.
	body="$(api GET "v1/edgehosts?limit=100" -H "ProjectUid: $uid")"
	states="$(printf '%s' "$body" |
		python3 -c '
import json, sys
for host in json.load(sys.stdin).get("items") or []:
    state = (host.get("status") or {}).get("health", {}).get("state") or ""
    ready = (host.get("status") or {}).get("state") or "unknown"
    print(host["metadata"]["name"], ready, state or "-")
' || true)"

	# Two states are complete, and both mean the record exists:
	#
	#   ready    the host registered and joins no cluster
	#   in-use   the host is in a cluster already
	#
	# `in-use` counts. This script waits for a record, and a host that a
	# cluster took holds one. An earlier version waited for `ready` alone, so
	# running this recipe on a live cluster polled for the whole timeout and
	# then reported hosts that had registered minutes or days before.
	# scripts/cluster.sh takes the same pair, for the same reason.
	ready=0
	missing=()
	for name in "${want[@]}"; do
		if printf '%s\n' "$states" | grep -qE "^${name} (ready|in-use)( |$)"; then
			ready=$((ready + 1))
		else
			missing+=("$name")
		fi
	done

	elapsed=$(($(date +%s) - start))

	if [ "$ready" -eq "${#want[@]}" ]; then
		info "every host registered after ${elapsed}s"
		exit 0
	fi

	if [ "$elapsed" -ge "$timeout" ]; then
		die "only $ready of ${#want[@]} host(s) registered after ${elapsed}s.
     These did not: ${missing[*]}
     To read the console of one:  just console <host>
     To read the agent log:       just host-status <host>
     See docs/src/troubleshooting.md."
	fi

	printf '    %3ds  %s of %s registered, waiting for: %s\n' \
		"$elapsed" "$ready" "${#want[@]}" "${missing[*]}"
	sleep "$interval"
done
