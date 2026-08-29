#!/usr/bin/env bash
# Build the cloud-init seed ISO for one host.
#
# The script reads templates/user-data.tmpl.yaml, replaces the placeholders,
# and writes the result into an ISO with the volume label CIDATA. The VM gets
# this ISO as a CD-ROM. cloud-init reads it at the first boot, installs the
# Palette agent, and the agent registers the host with your tenant.
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

vip_skip="${PALETTE_VIP_SKIP:-true}"
case "$vip_skip" in
true | false) ;;
*) die "PALETTE_VIP_SKIP must be true or false. You gave '$vip_skip'." ;;
esac

# ANCHOR: agenturl
# The agent install script comes from the agent-mode releases. An empty
# PALETTE_AGENT_VERSION gives the latest release.
if [ -n "${PALETTE_AGENT_VERSION:-}" ]; then
	agent_url="https://github.com/spectrocloud/agent-mode/releases/download/${PALETTE_AGENT_VERSION}/palette-agent-install.sh"
else
	agent_url="https://github.com/spectrocloud/agent-mode/releases/latest/download/palette-agent-install.sh"
fi
# ANCHOR_END: agenturl

mkdir -p "$seed_dir" "$build_dir"
chmod 700 "$seed_dir"

work="$build_dir/seed-$name"
rm -rf "$work"
mkdir -p "$work"

# The script passes the values in the environment. It does not put them in the
# program text, so a value with a quotation mark or a backslash is safe.
#
# There are two classes of value. A YAML scalar gets json.dumps, which writes a
# double-quoted scalar with the correct escapes. YAML 1.2 accepts JSON, so a
# project name such as O'Brien's Lab stays valid. A raw value goes in without
# quotation marks: the boolean must stay a boolean, and the URL already sits
# inside quotation marks in the template.
SEED_TEMPLATE="$root/templates/user-data.tmpl.yaml" \
	SEED_OUT="$work/user-data" \
	SEED_HOSTNAME="$name" \
	SEED_ENDPOINT="${PALETTE_ENDPOINT:-api.spectrocloud.com}" \
	SEED_PROJECT="${PALETTE_PROJECT:-Default}" \
	SEED_PASSWORD="${HOST_PASSWORD:-ubuntu}" \
	SEED_VIP_SKIP="$vip_skip" \
	SEED_AGENT_URL="$agent_url" \
	python3 -c '
import json, os, sys

quoted = {
    "@PALETTE_ENDPOINT@": os.environ["SEED_ENDPOINT"],
    "@PALETTE_EDGE_TOKEN@": os.environ["PALETTE_EDGE_TOKEN"],
    "@PALETTE_PROJECT@": os.environ["SEED_PROJECT"],
    "@HOSTNAME@": os.environ["SEED_HOSTNAME"],
    "@HOST_PASSWORD@": os.environ["SEED_PASSWORD"],
}
raw = {
    "@PALETTE_VIP_SKIP@": os.environ["SEED_VIP_SKIP"],
    "@AGENT_SCRIPT_URL@": os.environ["SEED_AGENT_URL"],
}
with open(os.environ["SEED_TEMPLATE"]) as f:
    text = f.read()
for key, value in quoted.items():
    text = text.replace(key, json.dumps(value))
for key, value in raw.items():
    text = text.replace(key, value)
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
    data = yaml.safe_load(f)
# The nested site config is a string in the outer document. Test it too.
for item in data.get("write_files", []):
    if item.get("path", "").endswith("site-config.yaml"):
        site = yaml.safe_load(item["content"])
        skip = site["stylus"]["vip"]["skip"]
        if not isinstance(skip, bool):
            sys.exit("error: stylus.vip.skip is not a boolean")
        if not site["stylus"]["site"]["edgeHostToken"]:
            sys.exit("error: the site config has an empty token")
' "$work/user-data" || die "the rendered user-data is not valid"

# cloud-init needs a meta-data file. The instance-id is the host name, so a
# rebuild of the same host gives the same seed ISO.
printf 'instance-id: %s\nlocal-hostname: %s\n' "$name" "$name" >"$work/meta-data"

# ANCHOR: mkiso
# The volume label must be CIDATA. cloud-init looks for a volume with that
# label and reads user-data and meta-data from it.
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
