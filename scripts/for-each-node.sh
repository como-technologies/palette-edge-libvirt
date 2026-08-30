#!/usr/bin/env bash
# Run a command one time for each node name in the topology.
#
# The script adds the node name as the last argument.
#
# Env: CLUSTER CONTROL_COUNT WORKER_COUNT
#
#   for-each-node.sh just seed
#   for-each-node.sh echo

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${CLUSTER:?}"
[ "$#" -ge 1 ] || die "give a command to run for each node"

for i in $(seq 1 "${CONTROL_COUNT:-1}"); do
	"$@" "${CLUSTER}-cp-$i"
done
for i in $(seq 1 "${WORKER_COUNT:-2}"); do
	"$@" "${CLUSTER}-wk-$i"
done
