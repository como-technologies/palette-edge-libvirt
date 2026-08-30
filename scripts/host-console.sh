#!/usr/bin/env bash
# Open the serial console of one host.
#
# The console is the only view of a host that has no address yet, so this is
# where a registration failure becomes visible. Press ctrl-] to leave it.
#
# The script tests the domain first. `virsh console` on an absent domain prints
# "failed to get domain" and names no correction, and on a stopped domain it
# waits without saying why.
#
#   host-console.sh <name>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?name required}"
need virsh

have_domain "$name" || die "domain $name is absent.
     To see the domains of this cluster:  just ls
     To make the machines:                just infra-up"

state="$(domain_state "$name")"
[ "$state" = "running" ] || die "domain $name is $state, so it has no console.
     To start it again:  just host-down $name && just infra-up"

info "console of $name. Press ctrl-] to leave it."
exec virsh console "$name"
