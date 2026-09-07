#!/usr/bin/env bash
# Test scripts/lib.sh: the paths and the guards that every recipe shares.
#
# Nothing here touches a real directory of yours. The path functions are pure
# text, and the guards read the environment only.

# shellcheck source=tests/assert.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assert.sh"

# --- the tooling directories ------------------------------------------------
#
# Rule: the checkout holds the source only. A PEL_ variable moves a directory,
# and a script that a recipe calls must agree with a script that you call by
# hand. These tests hold that agreement in place.

is "config_dir takes PEL_CONFIG_DIR" /tmp/c "$(PEL_CONFIG_DIR=/tmp/c config_dir)"
is "data_dir takes PEL_DATA_DIR" /tmp/d "$(PEL_DATA_DIR=/tmp/d data_dir)"
is "state_dir takes PEL_STATE_DIR" /tmp/s "$(PEL_STATE_DIR=/tmp/s state_dir)"
is "cache_dir takes PEL_CACHE_DIR" /tmp/k "$(PEL_CACHE_DIR=/tmp/k cache_dir)"
is "bin_dir takes PEL_BIN_DIR" /tmp/b "$(PEL_BIN_DIR=/tmp/b bin_dir)"

is "config_dir falls back to XDG_CONFIG_HOME" \
	/tmp/x/palette-edge-libvirt \
	"$(PEL_CONFIG_DIR='' XDG_CONFIG_HOME=/tmp/x config_dir)"

is "envs_dir sits under config_dir" /tmp/c/envs "$(PEL_CONFIG_DIR=/tmp/c envs_dir)"
is "env_link sits under config_dir" /tmp/c/env "$(PEL_CONFIG_DIR=/tmp/c env_link)"

# The API key is a tenant credential and PEL_CONFIG_DIR can name a checkout.
# This is the one path that must NOT follow that variable.
is "api_key_file ignores PEL_CONFIG_DIR" \
	/tmp/x/palette-edge-libvirt/api-key \
	"$(PEL_CONFIG_DIR=/somewhere/checkout XDG_CONFIG_HOME=/tmp/x api_key_file)"

is "project_state_dir is one directory for each project" \
	/tmp/s/iris "$(PEL_STATE_DIR=/tmp/s PALETTE_PROJECT=iris project_state_dir)"
refuses "project_state_dir refuses with no project" \
	env PALETTE_PROJECT= bash -c 'source scripts/lib.sh; project_state_dir'

# The tilde comes from a variable: a linter reads one inside quotation marks as
# a path that will not expand, and here it is the literal character we want.
tilde='~'
is "short_path writes the home directory as a tilde" "$tilde/x/y" "$(short_path "$HOME/x/y")"
is "short_path leaves another path alone" /etc/hosts "$(short_path /etc/hosts)"

# --- require_cluster_name ---------------------------------------------------
#
# The name goes to libvirt and to Palette. Each one refuses a different name.
# Palette applies its rule some minutes after the recipes build the machines
# with that name. Thus this guard changes a failed build into a message in one
# second.

accepts "a name of 3 characters passes" require_cluster_name abc
accepts "a name of 12 characters passes" require_cluster_name abcdefghijkl
accepts "a hyphen inside the name passes" require_cluster_name pe-lab
accepts "a number inside the name passes" require_cluster_name lab2

refuses_with "13 characters: the bridge would not fit" \
	"network device takes 15" require_cluster_name abcdefghijklm
refuses_with "2 characters: Palette refuses the cluster" \
	"less than 3 characters" require_cluster_name ab
refuses_with "an upper case letter is refused" \
	"lower case letters" require_cluster_name Lab
refuses_with "a trailing hyphen is refused" \
	"ends with a letter or a number" require_cluster_name lab-
refuses_with "a leading number is refused" \
	"starts" require_cluster_name 1lab
refuses_with "an empty name is refused" \
	"CLUSTER_NAME" require_cluster_name ""

# --- require_pod_cidr -------------------------------------------------------
#
# This guard prevents a failure that occurs later and gives no message. The
# nodes become Ready. kubectl operates. Palette stays in Provisioning, because
# the agent cannot resolve a name. The pack default value 192.168.0.0/16 causes
# this condition.

accepts "the default pod range passes" \
	env POD_CIDR=10.244.0.0/16 CLUSTER_SUBNET=192.168.140 \
	bash -c 'source scripts/lib.sh; require_pod_cidr'
accepts "a pod range that misses the subnet passes" \
	env POD_CIDR=172.16.0.0/16 CLUSTER_SUBNET=192.168.210 \
	bash -c 'source scripts/lib.sh; require_pod_cidr'
refuses_with "the pack default 192.168.0.0/16 swallows the cluster subnet" \
	"Calico gives no NAT" \
	env POD_CIDR=192.168.0.0/16 CLUSTER_SUBNET=192.168.140 \
	bash -c 'source scripts/lib.sh; require_pod_cidr'
refuses_with "a pod range equal to the cluster subnet is refused" \
	"Calico gives no NAT" \
	env POD_CIDR=192.168.140.0/24 CLUSTER_SUBNET=192.168.140 \
	bash -c 'source scripts/lib.sh; require_pod_cidr'

# --- the libvirt connection -------------------------------------------------
#
# The session connection is what keeps the CI runner out of the libvirt group,
# and the pool has to follow it: /var/lib/libvirt/images belongs to root, so a
# session daemon can write nothing there.

refuses "qemu:///system is not a session" \
	env LIBVIRT_DEFAULT_URI=qemu:///system bash -c 'source scripts/lib.sh; libvirt_session'
accepts "qemu:///session is a session" \
	env LIBVIRT_DEFAULT_URI=qemu:///session bash -c 'source scripts/lib.sh; libvirt_session'
refuses "no URI means the system connection" \
	env -u LIBVIRT_DEFAULT_URI bash -c 'source scripts/lib.sh; libvirt_session'

is "a system pool sits under /var/lib/libvirt/images" \
	/var/lib/libvirt/images/pe \
	"$(LIBVIRT_DEFAULT_URI=qemu:///system pool_target pe)"
is "a session pool sits in the home directory" \
	/tmp/d/pools/pe \
	"$(LIBVIRT_DEFAULT_URI=qemu:///session PEL_DATA_DIR=/tmp/d pool_target pe)"

# --- tfstate_has_resources --------------------------------------------------
#
# The state is the only record that connects this checkout to the objects in
# Palette. `cluster-down` reads this test and then decides to do nothing or to
# continue. `remove-project` reads it and then decides to delete the directory.
#
# An incorrect answer causes one of two failures. It leaves objects in the
# tenant, or it deletes the only record of them.

work="$(tmpdir)"

: >"$work/empty.tfstate"
printf '%s' '{"version":4,"resources":[]}' >"$work/none.tfstate"
printf '%s' '{"version":4,"resources":[{"type":"spectrocloud_cluster_edge_native"}]}' \
	>"$work/some.tfstate"
printf '%s' 'this is not json' >"$work/broken.tfstate"

refuses "an absent state holds no object" tfstate_has_resources "$work/absent.tfstate"
refuses "an empty file holds no object" tfstate_has_resources "$work/empty.tfstate"
refuses "an empty resource list holds no object" tfstate_has_resources "$work/none.tfstate"
accepts "a state with a resource holds an object" tfstate_has_resources "$work/some.tfstate"
accepts "a state that cannot be read counts as holding an object" \
	tfstate_has_resources "$work/broken.tfstate"
