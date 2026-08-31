# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project rules

These are hard rules. They override convenience.

1. **Every action is a recipe.** Never run a one-off command, and never tell the
   user to click a button in a web interface when a command can do the task. If
   a task has no recipe, add the recipe to the `justfile` first, then run it.
2. **Every create recipe has a remove recipe.** When you add `x-up`, add
   `x-down`. When you add `x-fetch`, add `x-clean`. Everything is reversible.
3. **Every recipe is idempotent when possible.** Test the state, then act. If
   the object exists, call `skip` from `scripts/lib.sh` and return 0. A second
   `just infra-up             # layer 1: net, pool, image, seeds, VMs, WAIT for registration
just infra-down           # layer 1 down: host records, VMs, pool, net
just hosts-wait           # block until every host registers (the layer seam)
just hosts-deregister     # remove the Palette record of every host
just cluster-up           # layer 2: cluster profile + cluster, via OpenTofu
just cluster-down         # layer 2 down: destroys both; hosts and VMs stay
just cluster-plan         # the changes cluster-up would make, and nothing else
just cluster-show         # profile id, cluster id, console URL
just cluster-kubeconfig   # print the admin kubeconfig (stdout only)
just tofu-install         # pinned OpenTofu into ~/.local/bin, no root
just nuke                 # both layers + seeds + token + Palette project + env file

just projects             # local project env files, * marks default
just new-project NAME [d] # create Palette project + its env file + set default
just remove-project NAME  # twin: delete project, env file, and link
just default-project NAME # select the project that the recipes operate on
just palette-projects     # list tenant projects, verify PALETTE_PROJECT
just palette-hosts        # list hosts that registered
just palette-clusters     # list clusters in the project
just palette-packs NAME   # versions of one edge-native pack in Public Repo
just seed NAME            # build one CIDATA seed ISO
just host-up NAME [role]  # role is control or worker (default worker)
just host-status NAME     # agent install progress
just console NAME         # serial console, ctrl-] to exit
just ls                   # every cluster VM with state and address

just docs-serve           # book at http://localhost:3000 with live reload
source <(just bash-completion)   # recipe + argument completion for this shell
```

**A failing recipe prints its own message and nothing else.** `set
no-exit-message` in the justfile drops just's trailing `error: recipe `x` failed
on line N with exit code M`, which named a line of the justfile and buried the
correction that `die()` had just printed. The exit code is unchanged, and just's
*argument* errors (wrong number of positional arguments) still print. So every
`die()` message must name the fix — it is now the only thing the user sees.
Boolean settings take the bare form: `set no-exit-message`, not `:= true`, or
`just --fmt --check` fails.

There is no test suite. `just lint` is the check that must pass: `just --fmt
--check`, `lint-pairs.sh` (rule 2), `lint-params.sh`, `lint-includes.sh`
(rule 5), `shellcheck`, and `mdbook build docs`.

**mdBook does NOT fail on a missing anchor.** It fails on a missing *file*, but a
`{{#include file:anchor}}` whose anchor was renamed renders as a silent empty
code block. That is exactly the doc-rot rule 5 exists to prevent, and it bit us
during the layer rename. `scripts/lint-includes.sh` now checks both halves of
every include; it skips the escaped `\{{#include ...}}` example in rules.md and
accepts an anchor comment with a trailing marker (`<!-- ANCHOR: network -->`).

To test one script directly, call it with its environment set. The recipes pass
values in the environment, never as global state:

```bash
PALETTE_EDGE_TOKEN=x scripts/seed-iso.sh test-1 ./seeds ./build
NETWORK=pe-net SUBNET=192.168.140 BUILD_DIR=./build scripts/net-up.sh
```

## Architecture

**Two layers. Each owns objects on BOTH sides, and each `-down` removes
everything its `-up` made.** This is the rule that keeps teardown honest.

| Layer | Workstation | Palette | Recipes |
| --- | --- | --- | --- |
| infrastructure | network, pool, disks, VMs | **host records** | `infra-up` / `infra-down` |
| cluster | **the OpenTofu state** | profile, cluster | `cluster-up` / `cluster-down` |

**The seam is registration.** `infra-up` does not return until every host is
`ready` in Palette (`hosts-wait.sh`, 900s default via `REGISTER_TIMEOUT`),
because a VM that never registered is useless to the cluster layer.

**Measured baseline, three full round trips, 1 control + 2 workers on the
Thelio.** Every step of both tables in `docs/src/introduction.md`, except
`host-setup`, which needs a restart:

| Step | run 1 | run 2 | run 3 | mean |
| --- | --- | --- | --- | --- |
| `tofu-install` | (present) | 2.1s | 1.9s | 2.0s |
| `new-project` | 2.3s | 2.9s | 2.7s | 2.6s |
| `infra-up` | 209s | 179s | 187s | **192s** |
| `cluster-up` | 636s | 668s | 634s | **646s** |
| `cluster-kubeconfig` | 0.4s | 2.7s | 0.4s | 1.2s |
| `cluster-down` | 40s | 46s | 40s | **42s** |
| `infra-down` | 9.6s | 7.0s | 8.9s | 8.5s |
| `remove-project` | 4.1s | 3.5s | 3.3s | 3.6s |
| forward total | | | | **843s (14m)** |
| reverse total | | | | **54s** |

`api-key-set`, `api-key-clear`, `image-clean`, and `tofu-uninstall` each measure
under 0.1s. The cloud image download sits inside `infra-up` and costs less than
the variance in registration: runs 2 and 3 downloaded it and still beat run 1,
which had it cached. **Teardown is 16 times faster than build.**

**Hosts are tied to clusters; VMs are never reused.** That decision is what makes
`infra-down` safe to deregister host records — a record whose VM is gone is
garbage. Rebuild rather than repair.

`infra-down` refuses while the project holds a Palette cluster: a cluster whose
machines vanished cannot be repaired. `nuke` = `cluster-down` + `infra-down` +
seeds + token + project + env file; the cloud image, the API key, and OpenTofu
survive because none of them belongs to one project.


The tooling uses Palette **agent mode**, not Edge Native. Each host boots the stock
Ubuntu cloud image and cloud-init installs the Palette agent. The repo builds no
OS image, so it needs no Docker and no CanvOS.

The workstation owns the virtual machines. Palette SaaS owns the cluster profile
and the cluster. **The seed ISO is the only link between the two.**

```
project env  ──►  scripts/seed-iso.sh  ──►  $PEL_DATA_DIR/seeds/NAME-seed.iso
                                          │
$PEL_CACHE_DIR/images/noble-...img  ──────┼──►  virt-install --import  ──►  VM
      (qemu-img copy + resize)                                              │
                                                    cloud-init installs     │
                                                    the agent, registers    │
                                                                            ▼
                                                                  Palette hosts
```

**Do not reintroduce Edge Native or CanvOS.** It was tried and removed in
2da762e. There is no prebuilt Edge installer ISO to download (CanvOS ships no
release assets), so that path requires a local CanvOS build, and CanvOS requires
Docker — which the agent-mode docs explicitly tell you not to install on the
host.

### The layers

- `justfile` — the only interface. Holds configuration and thin recipes. Also
  computes every path and exports it, so the scripts never guess.
- `scripts/*.sh` — all logic. Each script takes its input from the environment,
  so `shellcheck` can test it and you can run it alone.
- `templates/` — `network.xml` and `user-data.tmpl.yaml`. Both use `@NAME@`
  placeholders that a script replaces.
- `terraform/` — the cluster layer, HCL only. `scripts/cluster.sh` is the ONLY
  caller; never run `tofu` by hand (rule 1). `.terraform.lock.hcl` is committed;
  nothing else generated lands here, because the script sets `TF_DATA_DIR`.
- `docs/` — the mdBook. `docs/src/` is the prose. `docs/gruvbox/` and
  `docs/mermaid*.js` are generated by `just docs-theme`; they are committed.

### Three details that are easy to break

**There is no OS install.** `virt-install --import` boots a copy of the cloud
image. `host-up.sh` does `qemu-img convert` then `qemu-img resize`; cloud-init
grows the filesystem. Do not add installer media or boot-order logic.

**Seed values have two classes.** In `user-data.tmpl.yaml` the placeholders carry
no quotation marks. `seed-iso.sh` wraps *scalars* with `json.dumps` (valid
double-quoted YAML, so `O'Brien's Lab` survives), but substitutes
`@PALETTE_VIP_SKIP@` and `@AGENT_SCRIPT_URL@` **raw** — the first must stay a
YAML boolean, the second already sits inside shell quotes. Adding quotes in the
template breaks both. The script rejects leftover placeholders, an empty token,
and a non-boolean `vip.skip`.

**`PALETTE_PROJECT` fails silently.** A wrong project name produces no error
anywhere: the host boots, the agent runs, and it simply never appears in
Palette. `just palette-projects` catches it in a second. Run it before debugging
anything else about registration.

### The cluster layer (OpenTofu)

**The pod range MUST be replaced.** `edge-k8s` defaults to
`networking.podSubnet: 192.168.0.0/16`, which holds every subnet `new-project`
allocates (192.168.140–199) *and* most workstation LANs. Calico does not SNAT to
a destination inside its own pool, so pods cannot reach `$CLUSTER_SUBNET.1:53`
(libvirt dnsmasq) and every lookup times out. Symptom is late and quiet: nodes
go Ready, `kubectl` works, and Palette sits in `Provisioning` forever because
`cluster-management-agent-lite` cannot resolve `api.spectrocloud.com`.
`POD_CIDR` (default `10.244.0.0/16`) is spliced into the pack values with
`replace()` in `cluster-profile.tf` — plus a `precondition` on the default
string, because a `replace` that matches nothing is silent. The service range
`192.169.0.0/16` is fine and stays. `cluster.sh:require_pod_cidr` catches the
overlap before anything is created.

**Palette keeps deleted clusters in the list.** `v1/spectroclusters` returns them
with `status.state == "Deleted"` for ever. Counting every item made `infra-down`
refuse permanently after a correct `cluster-down`. `cluster_count()` in
`palette-lib.sh` filters them; `infra-down.sh`, `project-remove.sh`, and
`palette-api.sh clusters` all go through it. Never count that list raw.

**A cluster ALWAYS needs a VIP.** Palette rejects an Edge Native cluster with no
control plane endpoint — `Parameter 'Host endpoint' should not be empty` — for
one control-plane node exactly as for three. `CLUSTER_VIP` is therefore never
empty (default `$CLUSTER_SUBNET.10`, below the DHCP pool), and
`PALETTE_VIP_SKIP` is now **false** so the agent installs kube-vip to claim it.
Those two live in different layers: `cluster.sh` refuses when they disagree,
because a VIP that nothing answers fails only after an hour of provisioning.
Flipping `PALETTE_VIP_SKIP` needs `seed-clean` + `infra-down` + `infra-up`.
`host_config { host_endpoint_type }` is a *different* thing (service endpoints)
and does not fix that error.

**The agent-mode OS pack is `edge-native-byoi` with the Agent Mode preset**, not
the pack literally named `byoi-agent-mode` (that one exists in Public Repo and
is `system_state: deprecated`). The preset is just values:
`options.system.uri: "NA"` plus the `# spectrocloud.com/enabled-presets:
Deployment Mode:byoi-agent-mode` marker comment that the console reads. Vendored
in `terraform/values/edge-native-byoi.yaml`; a `lifecycle.precondition` fails the
plan if the header version disagrees with `OS_PACK_VERSION`.

**A pack name is not unique across clouds.** `cni-calico` exists for aws, gcp,
edge-native, and more, so every `data "spectrocloud_pack"` sets
`cloud = ["edge-native"]` and `registry_uid` from `data "spectrocloud_registry"
"Public Repo"`. A wrong-cloud pack is rejected only when Palette builds the
profile.

**An agent-mode edge host's uid IS its name.** `metadata.uid == metadata.name`,
because the seed sets `stylus.site.name`. `data "spectrocloud_appliance"` returns
that name as `id`, so `cluster.tf` needs no uid lookup table — it reads one
appliance per topology name, and the read itself proves the host registered.

**Never chmod the whole state directory.** `TF_DATA_DIR` lives under it and holds
the provider binary; a blanket `chmod 600` gives `fork/exec ...: permission
denied` on the next run. `protect_state` in `cluster.sh` uses `-maxdepth 1`.

**`just` has no `state_directory()`.** The justfile builds the XDG state path by
hand: `env_var_or_default("XDG_STATE_HOME", home_directory() / ".local/state")`.

**Packs API filter syntax has no spaces around AND.**
`filters=spec.name=edge-k8sANDspec.cloudTypes=edge-native`, URL-encoded.
`spec.cloudTypes` matches inside the array; `spec.cloudType` (singular) silently
returns 0 items. `just palette-packs NAME` wraps it.

**The API key never becomes a variable.** `cluster.sh` exports
`SPECTROCLOUD_APIKEY`/`SPECTROCLOUD_HOST`, so no key reaches the state or a plan
file. The state DOES hold the admin kubeconfig, hence 0700 dir and 0600 files.

### Naming

`CLUSTER_NAME` (default `pe`) prefixes every libvirt object: network `pe-net`, pool
`pe-pool`, domains `pe-cp-N` and `pe-wk-N`. The libvirt domain name and the
Palette Edge Host name are always the same, so `just ls` and the Palette host
list line up. Two labs coexist if `CLUSTER_NAME` and `CLUSTER_SUBNET` both differ.

## Configuration

**The checkout holds source only.** Every file worth keeping lives in an XDG
directory, so `rm -rf` on the checkout destroys nothing:

```
~/.config/palette-edge-libvirt/   api-key, envs/<project>.env, env -> envs/X.env
~/.local/share/palette-edge-libvirt/   seeds/, build/
~/.local/state/palette-edge-libvirt/<project>/   terraform.tfstate, tofu/ (TF_DATA_DIR)
~/.cache/palette-edge-libvirt/   images/, tofu/
~/.local/bin/tofu                 just tofu-install puts it here, no root
```

`PEL_CONFIG_DIR`, `PEL_DATA_DIR`, `PEL_STATE_DIR`, `PEL_CACHE_DIR`, and
`PEL_BIN_DIR` override each one. The justfile computes them with
`config_directory()` / `data_directory()` / `cache_directory()` and **exports**
them; `lib.sh` has `config_dir`, `data_dir`, `state_dir`, `cache_dir`,
`project_state_dir`, `bin_dir`, `envs_dir`, `env_link`, `env_pointer`, and
`short_path`, each falling back to the XDG variable so a script still works when
called directly.
`api_key_file` deliberately ignores `PEL_CONFIG_DIR` — that variable can point
at a checkout, and a tenant credential must never land in one.

**The checkout holds no config file at all.** A `set` in a justfile takes a
const — no function call, and no `~` or `$HOME` expansion — so `dotenv-path`
cannot name the config directory. `dotenv-command` can, because a command runs
in a shell:

```just
set dotenv-command := 'scripts/dotenv.sh'
```

`just` runs that from the justfile directory (verified, even when invoked from a
subdirectory), reads stdout as an env file, and lets the **process environment
win**, so `WORKER_COUNT=3 just infra-up` still overrides. `dotenv.sh` follows
`~/.config/palette-edge-libvirt/env -> envs/<project>.env` and cats it. That
link is the only record of the choice, so every checkout agrees. With no link
the script prints nothing and raises **no error** — the recipes silently fall
back to the justfile defaults, so `just config` and `just projects` both report
it and name the fix. Setting `dotenv-command` also makes `just` ignore any
stray `.env` in the checkout entirely (verified).

`just default-project NAME` makes the link; `just new-project` creates the
tenant project, writes the env file (auto-allocating a free `CLUSTER_NAME` and
`CLUSTER_SUBNET`, scanning both the env files and live libvirt networks), and sets
it default.

Palette keeps a project description in `metadata.annotations.description`, not
in a `description` field.

**Never put the API key in a project env file.** A Palette API key has no scope
of its own — `spec` is only `{expiry, user}`, so it carries every permission of
its owner, and only tenant-level roles can manage edge tokens. It lives in
`~/.config/palette-edge-libvirt/api-key` via `just api-key-set`, read by
`need_api_key` in `palette-lib.sh`. An earlier version copied it into each
`envs/*.env`; `remove-project` then destroyed a tenant credential that Palette
will not show again. Call `need_api_key` early in a script, never only inside a
pipeline — `die` in a pipeline exits the subshell and the reader fails with a
traceback instead of the message.

**The token API reads and writes different shapes.** A GET returns
`spec.defaultProject: {name, uid}`, but a create or update takes
`spec.defaultProjectUid` as a bare uid string. Sending the read shape back
returns HTTP 204/201 with **no binding applied** — silent, and an unbound token
registers hosts into no project. Never infer a Palette write shape from its
read shape.

**Never hand libvirt a file inside the repo.** libvirt chowns every file a
domain uses to `libvirt-qemu` and does not restore it when a start fails, and
the seed directory is 0700 so the qemu user cannot enter it anyway. `host-up.sh` copies
the seed into the storage pool and attaches that copy; `host-down.sh` and
`host-eject.sh` delete pool files. `seed-iso.sh` unlinks its output first, so a
seed that libvirt captured can still be rebuilt without sudo.

**cloud-init runs `runcmd` with dash, not bash.** `set -o pipefail` there gives
"Illegal option" and kills the whole script, and cloud-init reports it only in
`cloud-init status --long` — the host boots fine and silently does nothing. Put
real work in a `write_files` script with a `#!/bin/bash` line.

**The agent needs one reboot.** `palette-agent install` enables the
`spectro-palette-agent-*` services but leaves them `inactive dead`; they run at
boot stages. The template uses cloud-init `power_state` with a condition on the
marker file, so a correct install reboots once and a failed one stays up for
diagnosis.

**`set -o pipefail` turns a first-stage failure into a silent exit.** Every
script sets `-euo pipefail`, so `x="$(virsh pool-dumpxml "$POOL" | sed ... )"`
with an absent pool ends the script **with no message at all**, and it skips the
`[ -n "$x" ] || die "..."` that was written for exactly that case.
`host-down.sh` hit this: it destroyed and undefined the domain, then died
silently before it deleted the disk, so a 100 GB file stayed with nothing to
name it. Any command substitution whose first stage can fail needs `|| true`,
and the test below it is what reports the condition. The same bug made
`just projects` print nothing when an environment file held no `CLUSTER_NAME`,
because `grep` calls "no match" a failure.

**libvirt does NOT refuse to remove a network or a pool that is in use.**
`net-destroy` on a network that a running domain uses returns 0. The domain
keeps running with a bridge that is gone: no address, no registration, and no
message anywhere. `net-down.sh` and `pool-down.sh` therefore test with
`domains_using_network` and `domains_using_pool` in `lib.sh`, and take `FORCE=1`.
An earlier `net-down.sh` tested the exit code of `net-destroy` for this, which is
always 0, so that guard never fired.

**`rmdir` needs write permission on the PARENT.** `/var/lib/libvirt/images` is
`drwx--x--x root:root`, so `pool-down` cannot remove its own pool directory even
though `pool-up` chowned that directory to you. The directory is traversable and
not readable, so `[ -d ]` works and `ls` does not. Report the two reasons apart:
"still holds a file" is worth saying, "the parent belongs to root" is not a
fault.

**Do the root work before the object exists.** `pool-up.sh` used to
`pool-define-as` and then `sudo chown`. A workstation with no cached password
then had a pool that was defined, inactive, and unusable, and the next run said
"already defined" and failed in the same place. All of the sudo now happens
first, and the script names the two commands to run by hand when there is no
terminal and no cached password.

**A recipe must not wait for something that cannot happen.** `hosts-wait` polled
the API for the full `REGISTER_TIMEOUT`, 900s, when there were no virtual
machines at all. It now asks libvirt first: a name with no domain and no record
fails in a second. It also counts `in-use` as registered, exactly as
`cluster.sh:require_ready_hosts` does, or a second run on a live cluster waits
the whole timeout for hosts that registered days before.

**The build directory holds the token too.** `seeds/` was 0700 with 0600 files,
and `build/seed-<name>/user-data` — the same token, rendered — was left at the
default mode in a world-readable directory. Both directories are 0700 now and
both files are 0600. `remove-project` deletes the seeds of its own cluster as
well, because only `nuke` used to remove them.

**`just config` may hold no default of its own.** It repeated every default from
the justfile, one drifted, and the recipe reported a 60 GB control plane disk
while it built a 100 GB one. The recipe passes every computed value now, and the
script prints what it receives.

**The `libvirt` group is root.** The system socket is `root:libvirt` and
`libvirtd.conf` sets `auth_unix_rw = "none"`, so a member drives a daemon that
runs as root: define a domain whose disk is `/dev/nvme0n1`, start it, read and
write every file on the workstation. No sudoers file changes this. CI therefore
runs on `qemu:///session`, where libvirtd runs as the runner and opens only what
the runner can open, and `runner-setup` takes the account OUT of the group.
Fine-grained polkit ACLs do not help: they gate object and verb, not the disk
path.

**A session cannot make a network, a pool under /var/lib/libvirt, or read the
lease table.** `runner-setup` makes one *system* network as root and the session
domains attach to its bridge (`--network bridge=br-X`, not `network=X`), which
keeps the subnet, DHCP and the VIP. That needs `setcap cap_net_admin+ep` on
`qemu-bridge-helper` (Ubuntu ships it unprivileged) and `allow br-X` in
`/etc/qemu/bridge.conf`. The pool moves to the home directory. `host-ip.sh` reads
`ip neigh` on the bridge, because the lease table belongs to the system
connection. `libvirt_session` and `pool_target` in `lib.sh` pick the path;
`preflight` skips the libvirt-group test in a session.

**`systemctl list-units` lists LOADED units.** A stopped, unloaded service does
not appear, so a check built on it reports "not installed" while the unit file
is still there — and `svc.sh install` then refuses with "exists" for ever. Test
the FILE: `runner_units()` in `lib.sh`.

**A Palette cluster name needs 3 characters at least**, matching
`[a-z][a-z0-9-]{1,31}[a-z0-9]`, and the libvirt bridge caps it at 12. Palette
applies its rule when it makes the cluster, minutes after `infra-up` built the
machines under the same name, so `require_cluster_name` in `lib.sh` runs from
`net-up.sh` and fails in a second.

**Test for a usable key, not for the key FILE.** `infra-down` tested
`[ -s "$(api_key_file)" ]`, so a key given in the environment — the documented
way, and the only way CI gives it — skipped the whole Palette half silently and
orphaned a host record for every machine it deleted. Use `have_api_key`.

**A workflow must not repeat a justfile value.** The e2e workflow held its own
`CLUSTER_NAME`, subnet, VIP and pod range; they drifted on the first change.
`just ci-env` prints them and the workflow reads that into `GITHUB_ENV`. Same
lesson as `just config`.

**An interactive `gh` wrapper breaks `set -u`.** A `gh` shell function is
exported into child shells, and one that reads `$GH_REPO` with no default aborts
under `set -u` — silently, when stderr is redirected. Scripts call `command gh`.

**`virsh` tables have a header row.** `domiflist` and `net-dhcp-leases` output
parsed with plain awk field numbers matches the header: `host-ip.sh` reported
the address as "Protocol" until it matched on the shape of a MAC instead.

**`CLUSTER_NAME` takes 12 characters at most.** The libvirt bridge is `br-$CLUSTER_NAME`
and a Linux interface name takes 15. Over that, libvirt defines the network fine
and fails at start with "Numerical result out of range". `net-up.sh` checks the
length up front, and also refuses any `@PLACEHOLDER@` that survives the sed —
libvirt accepts a literal `@BRIDGE@` as a name and then builds no device.

**`UID` is readonly in bash.** `UID=x python3 ...` fails with "readonly
variable"; the helpers use `PEL_UID`. shellcheck does not catch this.

**Each project owns a registration token.** `new-project` creates one bound to
the project (`spec.defaultProject.uid`) and writes `spec.token` straight into
the env file, so no token is ever copied by hand. `remove-project` deletes the
token *before* the project: Palette returns HTTP 500
`DeletionResourceInUseError` if a token still names the project. Token API is
`/v1/edgehosts/tokens`.

## Recipe parameters name a kind, not a position

`host-up host role="worker"`, `default-project project`. The bash completion
reads recipe names from `just --summary` and parameters from `just --dump
--dump-format json`, then completes by parameter name — so it holds no list of
recipes and a new recipe completes for free. Keep parameters named `host`,
`project`, `role`, `action`, or add the new kind to `_PEL_KINDS` in
`scripts/bash-completion.sh` (free-text kinds such as `pack` go in
`_PEL_KINDS_FREE`). `scripts/lint-params.sh` fails the build if a parameter name
is unknown — the `[private] _tofu action` recipe is why `action` is a kind.
`templates/project.env` is the template that `new-project` fills in, and it
carries the anchors that the docs include, so **edit it when you add a
variable**, or the docs go stale. It was `.env.example` until the tooling wrote
every project file; nothing copies it by hand now. The completion reads the
project list from `just --evaluate envs_dir`, so it followed the files out of
the checkout with no change of its own.

Every `justfile` variable uses `env_var_or_default`, so the repo works with no
project at all. Any value can be overridden for one command:
`WORKER_COUNT=3 just infra-up`.

## Secrets

`PALETTE_EDGE_TOKEN` is the sensitive value. It lives in the project env file
and is written into every seed ISO. Both are outside the checkout now. The envs
directory and the seeds directory are both mode 0700, and each env file and each
ISO is mode 0600.

Never print the token. `just config` and `just preflight` print only its length.
Keep it that way. After a host installs, `just host-eject NAME` removes the seed
ISO from the VM so the host holds no copy.

## Verified vs unverified

**Both layers are verified end to end** against the live tenant, on
`thelio-lab` / `theliolab`, 1 control + 2 workers:

- `infra-up` builds the machines and all three hosts register (170s measured).
- `cluster-up` builds the profile and the cluster, and Palette reports `Running`
  with every condition true. Wall clock 10m34s-11m08s for 1 control and 2
  workers on the Thelio, measured over three builds.
- `cluster-kubeconfig` yields a working kubeconfig. Its server is the VIP
  (`https://$CLUSTER_VIP:6443`), which the workstation reaches over the bridge.
  Three nodes Ready on PXK-E `v1.33.13`, `podCIDR` from `POD_CIDR`, Calico up,
  and `spectro-storage-class` is the default StorageClass.
- `cluster-down` destroys both objects in about 35s.
- `cluster-verify` passes every test on that cluster.

**Continuous integration is verified end to end on `qemu:///session`**, against
the live tenant, on the `cilab` lab (192.168.210.0/24), with the runner as
`ghrunner` in groups `ghrunner,kvm` and NOT `libvirt`:

- the whole job in 16m28s: nuke, new-project, infra-up, cluster-up,
  cluster-verify, nuke. The workstation and the tenant are both empty after it.
- `virt-install --import` works with `--network bridge=br-cilab` in a session,
  and the dnsmasq of the system network serves DHCP to the session taps.
- kube-vip claims the VIP over a session tap: the API server answers at
  `https://192.168.210.10:6443`. It does not answer ICMP, so `ping` proves
  nothing there; the TCP connection is the test.

`stylus.site.name` is confirmed good: it is not in the documented agent-mode
example, but it is what makes the libvirt domain name and the Palette host name
identical, and registration works with it.

Pinned combination that is known to work: `edge-native-byoi` 2.1.0 (Agent Mode),
`edge-k8s` 1.33.13, `cni-calico` 3.32.1, `csi-local-path-provisioner` 0.0.37,
provider `spectrocloud` 0.29.9, OpenTofu 1.12.6.

Still unverified: more than one control-plane node (`CONTROL_COUNT=3`, where
kube-vip actually has to fail over), a pack re-pin on a running cluster, and
`runner-setup-undo` (the twin exists and is linted, and nothing has run it).
