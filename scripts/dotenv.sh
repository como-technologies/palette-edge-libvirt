#!/usr/bin/env bash
# Print the environment file of the default project.
#
# `set dotenv-command` in the justfile runs this script and reads the output as
# an environment file. The script therefore replaces the .env file that the
# checkout held before.
#
# `just` gives a setting no function and no tilde, so the justfile cannot name
# a directory in your home directory. It can name a command, and a command
# computes the path. This is the reason that the tooling keeps no file in the
# checkout.
#
# `just` runs this script for every recipe, so the script does one test and one
# read. It prints nothing when there is no default project, and `just` then
# gives each recipe its default value.
#
#   dotenv.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

link="$(env_link)"

# -e follows the link. A link to a file that another recipe removed therefore
# gives no output and no error.
[ -e "$link" ] || exit 0

cat "$link"
