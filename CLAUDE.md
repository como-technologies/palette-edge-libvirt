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
   `just cluster-up` must create nothing.
4. **Every recipe has a documentation comment.** `just` renders it as help text.
5. **The docs include the source. They never copy it.** Add `# ANCHOR: name` and
   `# ANCHOR_END: name` to the source file, then reference it from
   `docs/src/*.md` as `{{#include ../../path:name}}`. `just lint` builds the
   book, so a broken path or missing anchor fails the build.
6. **All prose is ASD-STE100** (Simplified Technical English). This covers the
   docs, the README, this file, and code comments. Short sentences (20 words max
   in procedures). Active voice. Present tense. One instruction per sentence.
   Keep articles. One word, one meaning. No idioms and no figures of speech.

## Commands

```bash
just                      # list every recipe with its help text
just config               # show effective config and where it came from
just preflight            # test tools, permissions, capacity (makes no change)
just lint                 # justfile format + shellcheck + mdbook build
just fmt                  # format the justfile

just cluster-up           # full lab: preflight, infra, image, seeds, VMs
just cluster-down         # remove the VMs, keep infra and image
just nuke                 # cluster-down + infra-down + seed-clean

just projects             # local project env files, * marks default
just new-project NAME [d] # create Palette project + envs/NAME.env + set default
just remove-project NAME  # twin: delete project, env file, and link
just default-project NAME # re-point .env at another project
just palette-projects     # list tenant projects, verify PALETTE_PROJECT
just palette-hosts        # list hosts that registered
just seed NAME            # build one CIDATA seed ISO
just host-up NAME [role]  # role is control or worker (default worker)
just host-status NAME     # agent install progress
just console NAME         # serial console, ctrl-] to exit
just ls                   # every lab VM with state and address

just docs-serve           # book at http://localhost:3000 with live reload
source <(just bash-completion)   # recipe + argument completion for this shell
```

There is no test suite. `just lint` is the check that must pass. It runs three
things: `just --fmt --check`, `shellcheck` on `scripts/*.sh`, and `mdbook build
docs`. The book build is also the test for every doc include.

To test one script directly, call it with its environment set. The recipes pass
values in the environment, never as global state:

```bash
PALETTE_EDGE_TOKEN=x scripts/seed-iso.sh test-1 ./seeds ./build
NETWORK=pe-net SUBNET=192.168.140 BUILD_DIR=./build scripts/net-up.sh
```

## Architecture

The lab uses Palette **agent mode**, not Edge Native. Each host boots the stock
Ubuntu cloud image and cloud-init installs the Palette agent. The repo builds no
OS image, so it needs no Docker and no CanvOS.

The workstation owns the virtual machines. Palette SaaS owns the cluster profile
and the cluster. **The seed ISO is the only link between the two.**

```
.env  ──►  scripts/seed-iso.sh  ──►  seeds/NAME-seed.iso (CIDATA)
                                          │
images/noble-server-cloudimg-amd64.img ───┼──►  virt-install --import  ──►  VM
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

- `justfile` — the only interface. Holds configuration and thin recipes.
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

`LAB_NAME` (default `pe`) prefixes every libvirt object: network `pe-net`, pool
`pe-pool`, domains `pe-cp-N` and `pe-wk-N`. The libvirt domain name and the
Palette Edge Host name are always the same, so `just ls` and the Palette host
list line up. Two labs coexist if `LAB_NAME` and `LAB_SUBNET` both differ.

## Configuration

All configuration lives in `.env`, loaded by `set dotenv-load`. Git ignores it.

`.env` is normally a **symlink** into `envs/<project>.env` — one file per
Palette project, so several labs coexist. `just default-project NAME` re-points
the symlink; `just new-project` creates the tenant project, writes the env file
(auto-allocating a free `LAB_NAME` and `LAB_SUBNET`, scanning both `envs/*.env`
and live libvirt networks), and sets it default. `envs/` is gitignored: those
files hold tokens. A plain `.env` still works — `just adopt-project NAME`
migrates one into the layout, `just unadopt-project` reverses it.

Palette keeps a project description in `metadata.annotations.description`, not
in a `description` field.

## Recipe parameters name a kind, not a position

`host-up host role="worker"`, `default-project project`. The bash completion
reads recipe names from `just --summary` and parameters from `just --dump
--dump-format json`, then completes by parameter name — so it holds no list of
recipes and a new recipe completes for free. Keep parameters named `host`,
`project`, `role`, or add the new kind to `_PEL_KINDS` in
`scripts/bash-completion.sh`. `scripts/lint-params.sh` fails the build if a
parameter name is unknown.
`.env.example` is the documented template and carries the anchors that
`docs/src/configuration.md` includes, so **edit `.env.example` when you add a
variable**, or the docs go stale.

Every `justfile` variable uses `env_var_or_default`, so the repo works with no
`.env` at all. Any value can be overridden for one command:
`WORKER_COUNT=3 just cluster-up`.

## Secrets

`PALETTE_EDGE_TOKEN` is the sensitive value. It lives in `.env` and is written
into every seed ISO. Both are gitignored. `seeds/` is mode 0700 and each ISO is
mode 0600.

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

Cluster profile and cluster creation happen in Palette and have no recipe yet.
That is the one remaining gap against rule 1. `scripts/palette-api.sh` already
has a working authenticated `api()` helper to build on; add both a create and a
remove recipe.
