#!/usr/bin/env bash
# Remove every object that the tooling made for this project.
#
# The recipe runs `infra-down` first, so the cluster layer and the machines are
# already gone when this script starts. This script removes what is left:
#
#   the seed ISO files and the build directory
#   the registration token
#   the Palette project
#   the environment file of the project
#
# The Ubuntu cloud image stays. It is a cache in ~/.cache, one copy for every
# project, so `just image-clean` removes it. The API key stays. It is a tenant
# credential, and no project recipe may delete it.
#
# `project-remove.sh` asks you to type the project name. Give FORCE=1 to answer
# in advance.
#
# This script is idempotent.
#
#   nuke.sh
#   FORCE=1 nuke.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

here="$(dirname "${BASH_SOURCE[0]}")"

need_project

info "remove the seeds and the build files"
rm -rf "$(data_dir)/seeds" "$(data_dir)/build"

# The token, the project, and the environment file. This recipe refuses while
# the project still holds a cluster or a host, so infra-down must run first.
"$here/project-remove.sh" "$PALETTE_PROJECT"

info "nothing of project $PALETTE_PROJECT is left"
printf '    The cloud image stays in %s. To remove it: just image-clean\n' \
	"$(short_path "$(cache_dir)/images")"
printf '    The API key stays in %s.\n' "$(short_path "$(api_key_file)")"
