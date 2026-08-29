#!/usr/bin/env bash
# Build the cloud-init seed ISO for one host.
#
# The script reads templates/user-data.tmpl.yaml, replaces the placeholders,
# and writes the result into an ISO with the volume label CIDATA. The VM gets
# this ISO as a second CD-ROM. The Edge installer reads it and registers the
# host with your Palette tenant.
#
# The ISO contains the registration token. The script writes it to the
# gitignored seeds/ directory with the file mode 0600.
#
# This script is idempotent. The same inputs give the same ISO.
#
#   seed-iso.sh <hostname> <seed-dir> <build-dir>

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?hostname required}"
seed_dir="${2:?seed dir required}"
build_dir="${3:?build dir required}"
root="$(repo_root)"

: "${PALETTE_EDGE_TOKEN:?PALETTE_EDGE_TOKEN is empty. See .env.example.}"

mkdir -p "$seed_dir" "$build_dir"
chmod 700 "$seed_dir"

work="$build_dir/seed-$name"
rm -rf "$work"
mkdir -p "$work"

# The script passes the values in the environment. It does not put them in the
# program text, so a value with a quotation mark or a backslash is safe.
#
# json.dumps writes a double-quoted YAML scalar with the correct escapes. YAML
# 1.2 accepts JSON, so a project name such as O'Brien's Lab stays valid.
SEED_TEMPLATE="$root/templates/user-data.tmpl.yaml" \
	SEED_OUT="$work/user-data" \
	SEED_HOSTNAME="$name" \
	SEED_ENDPOINT="${PALETTE_ENDPOINT:-api.spectrocloud.com}" \
	SEED_PROJECT="${PALETTE_PROJECT:-Default}" \
	python3 -c '
import json, os, sys

subs = {
    "@PALETTE_ENDPOINT@": os.environ["SEED_ENDPOINT"],
    "@PALETTE_EDGE_TOKEN@": os.environ["PALETTE_EDGE_TOKEN"],
    "@PALETTE_PROJECT@": os.environ["SEED_PROJECT"],
    "@HOSTNAME@": os.environ["SEED_HOSTNAME"],
}
with open(os.environ["SEED_TEMPLATE"]) as f:
    text = f.read()
for key, value in subs.items():
    text = text.replace(key, json.dumps(value))
leftover = sorted({w for w in text.split() if w.startswith("@") and w.endswith("@")})
if leftover:
    sys.exit("error: the template still has placeholders: " + ", ".join(leftover))
with open(os.environ["SEED_OUT"], "w") as f:
    f.write(text)
'

# Test that the result is valid YAML, if PyYAML is available. A bad seed makes
# a host that does not register, and that failure is slow to diagnose.
python3 -c '
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
with open(sys.argv[1]) as f:
    yaml.safe_load(f)
' "$work/user-data" || die "the rendered user-data is not valid YAML"

# cloud-init needs a meta-data file. The instance-id is the host name, so a
# rebuild of the same host gives the same seed ISO.
printf 'instance-id: %s\nlocal-hostname: %s\n' "$name" "$name" >"$work/meta-data"

# ANCHOR: mkiso
# The volume label must be CIDATA. cloud-init and the Palette Edge agent both
# look for a volume with that label.
out="$seed_dir/$name-seed.iso"
if command -v genisoimage >/dev/null; then
	genisoimage -quiet -output "$out" -volid CIDATA -joliet -rock \
		"$work/user-data" "$work/meta-data"
elif command -v xorriso >/dev/null; then
	xorriso -as mkisofs -quiet -o "$out" -V CIDATA -J -r \
		"$work/user-data" "$work/meta-data"
else
	die "install genisoimage or xorriso. Run: just host-setup"
fi
# ANCHOR_END: mkiso

chmod 600 "$out"
info "seed for $name: $out"
