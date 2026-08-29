#!/usr/bin/env bash
# Report the progress of the agent installation on one host.
#
# cloud-init installs the agent at the first boot. That takes some minutes,
# because it installs packages first. This script reads the state without a
# login on the console.
#
#   host-status.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"
here="$(dirname "${BASH_SOURCE[0]}")"

have_domain "$name" || die "domain $name is absent"

state="$(domain_state "$name")"
printf '%-14s %s\n' "domain" "$state"

if [ "$state" != "running" ]; then
	skip "start it with: just host-up $name"
	exit 0
fi

address="$("$here/host-ip.sh" "$name" 2>/dev/null || true)"
printf '%-14s %s\n' "address" "${address:-none yet}"

if [ -z "$address" ]; then
	skip "the host has no lease yet. cloud-init starts the network first."
	exit 0
fi

# The console log holds the cloud-init output. Read the domain log instead of a
# login, because the lab uses no SSH key.
printf '%-14s %s\n' "console" "just console $name"
printf '%-14s %s\n' "palette" "just palette-hosts"

cat <<'EOF'

To read the agent progress, open the console and log in as ubuntu:

  just console <name>
  sudo cloud-init status --long
  sudo journalctl -u cloud-final --no-pager | tail -40
EOF
