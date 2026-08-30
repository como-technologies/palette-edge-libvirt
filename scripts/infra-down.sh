#!/usr/bin/env bash
# Remove the infrastructure layer of one cluster.
#
# The layer holds every object that the tooling makes for the machines:
#
#   in Palette        the host record of each virtual machine
#   on the workstation the virtual machines, the storage pool, the network
#
# A layer removes everything that it made, on both sides. A host record has no
# use when its virtual machine is gone, so this script removes the records
# first. This is not a surprise: the recipe says so, and the layer above holds
# the cluster.
#
# The script refuses while the cluster layer exists. Palette keeps a cluster
# that has no machines, and that cluster is then impossible to repair.
#
# This script is idempotent. An empty layer gives a skip for each part.
#
# Env: CLUSTER POOL NETWORK
#
#   infra-down.sh

set -euo pipefail
# shellcheck source=scripts/palette-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/palette-lib.sh"

: "${CLUSTER:?}" "${POOL:?}" "${NETWORK:?}"
here="$(dirname "${BASH_SOURCE[0]}")"

need virsh

# --- 1. refuse while the layer above exists ---------------------------------

# The test needs the API. A workstation with no key still removes its own
# machines, so a missing key gives a warning and not an error.
if [ -n "${PALETTE_PROJECT:-}" ] && [ -s "$(api_key_file)" ] &&
	command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
	uid="$(project_uid "$PALETTE_PROJECT" 2>/dev/null || true)"
	if [ -n "$uid" ]; then
		# The count holds the live clusters only. Palette keeps the record
		# of a deleted one, and that record must not block this recipe.
		clusters="$(cluster_count "$uid" 2>/dev/null || echo 0)"
		if [ "${clusters:-0}" -gt 0 ]; then
			die "project $PALETTE_PROJECT holds $clusters cluster(s).
     The cluster layer sits above this one. Remove it first:
       just cluster-down
     A cluster whose machines are gone is impossible to repair."
		fi
	fi

	# --- 2. the Palette half of this layer ------------------------------
	#
	# MACHINES_GO=1: the machines go in step 3, so host-deregister.sh must
	# not print its advice to build the seed of each one again.
	CLUSTER="$CLUSTER" MACHINES_GO=1 "$here/hosts-deregister.sh"
else
	warn "no API key or no project, so the host records stay in Palette.
         To remove them later: just hosts-deregister"
fi

# --- 3. the machines --------------------------------------------------------

mapfile -t domains < <(virsh list --all --name | grep "^${CLUSTER}-" || true)

if [ "${#domains[@]}" -eq 0 ]; then
	skip "there are no ${CLUSTER}-* domains"
else
	info "remove ${#domains[@]} domain(s): ${domains[*]}"
	for domain in "${domains[@]}"; do
		POOL="$POOL" "$here/host-down.sh" "$domain"
	done
fi

# --- 4. the files that no domain names any more ------------------------------

# host-down.sh reads the file names from the definition of the domain, so a
# domain that goes without it leaves its disk with nothing to name it. Then
# host-down reports "absent", pool-down refuses to remove a directory that holds
# a file, and a 100 GB disk stays on the workstation for ever with no recipe
# that can reach it.
#
# The pool directory is /var/lib/libvirt/images/$CLUSTER, one for each cluster,
# so every file in it belongs to this layer. The domains are gone by now, which
# is what makes this safe.
pool_dir="$(virsh pool-dumpxml "$POOL" 2>/dev/null |
	sed -n 's:.*<path>\(.*\)</path>.*:\1:p' | head -n1 || true)"

if [ -n "$pool_dir" ] && [ -d "$pool_dir" ]; then
	mapfile -t orphans < <(find "$pool_dir" -maxdepth 1 -type f 2>/dev/null || true)
	if [ "${#orphans[@]}" -gt 0 ]; then
		info "remove ${#orphans[@]} file(s) that no domain names any more"
		for file in "${orphans[@]}"; do
			rm -f "$file" 2>/dev/null || sudo rm -f "$file"
			info "deleted $file"
		done
	fi
fi

# --- 5. the pool and the network --------------------------------------------

POOL="$POOL" "$here/pool-down.sh"
NETWORK="$NETWORK" "$here/net-down.sh"
