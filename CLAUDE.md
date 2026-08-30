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
just nuke                 # both layers + seeds + token + Palette project + env file

just projects             # local project env files, * marks default
just new-project NAME [d] # create Palette project + its env file + set default
just remove-project NAME  # twin: delete project, env file, and link
just default-project NAME # select the project that the recipes operate on
just palette-projects     # list tenant projects, verify PALETTE_PROJECT
just palette-hosts        # list hosts that registered
just seed NAME            # build one CIDATA seed ISO
just host-up NAME [role]  # role is control or worker (default worker)
just host-status NAME     # agent install progress
just console NAME         # serial console, ctrl-] to exit
just ls                   # every cluster VM with state and address

just docs-serve           # book at http://localhost:3000 with live reload
source <(just bash-completion)   # recipe + argument completion for this shell
```

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
| cluster | — | profile, cluster | `cluster-up` / `cluster-down` (Terraform, not built) |

**The seam is registration.** `infra-up` does not return until every host is
`ready` in Palette (`hosts-wait.sh`, 900s default via `REGISTER_TIMEOUT`),
because a VM that never registered is useless to the cluster layer and Terraform
needs the host UIDs. A full layer-1 build measured 2m43s for 1 control + 2
workers.

**Hosts are tied to clusters; VMs are never reused.** That decision is what makes
`infra-down` safe to deregister host records — a record whose VM is gone is
garbage. Rebuild rather than repair.

`infra-down` refuses while the project holds a Palette cluster: a cluster whose
machines vanished cannot be repaired. `nuke` = `infra-down` + seeds + token +
project + env file; the cloud image and API key survive because neither belongs
to one project.


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
~/.local/share/palette-edge-libvirt/   seeds/, build/  (terraform state goes here)
~/.cache/palette-edge-libvirt/   images/
```

`PEL_CONFIG_DIR`, `PEL_DATA_DIR`, and `PEL_CACHE_DIR` override each one. The
justfile computes them with `config_directory()` / `data_directory()` /
`cache_directory()` and **exports** them; `lib.sh` has `config_dir`, `data_dir`,
`cache_dir`, `envs_dir`, `env_link`, `env_pointer`, and `short_path`, each
falling back to the XDG variable so a script still works when called directly.
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
`project`, `role`, or add the new kind to `_PEL_KINDS` in
`scripts/bash-completion.sh`. `scripts/lint-params.sh` fails the build if a
parameter name is unknown.
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

Verified against the live tenant: the API key works, `v1/projects` and
`v1/edgehosts` return correctly, and `just palette-projects` / `just
palette-hosts` both run clean.

Not yet verified end to end: no host has completed a boot and registered. The
`stylus.site` schema matches the published agent-mode example, and
`stylus.site.name` is included to keep the libvirt domain name and the Palette
host name identical — but that field is not in the documented example, so if
registration misbehaves, suspect it first.

The cluster layer has no recipe yet: the profile and the cluster are made by
hand in Palette. That is the one remaining gap against rule 1, and `cluster-up`
/ `cluster-down` are reserved for the Terraform that closes it. `scripts/palette-api.sh` already
has a working authenticated `api()` helper to build on; add both a create and a
remove recipe.
