# CLAUDE.md

Guidance for Claude Code when working in this repository.

**The book is the documentation. This file is not a second copy of it.**
`docs/src/` holds each fact, with the error text and the correction. `just lint`
examines the book. Read the page before you change the item that it describes.
When you learn a new fact, put it in the book. Do not add it to this file.

## Read this first

| Question | Page |
| --- | --- |
| What are the rules here? | `docs/src/rules.md` |
| What does each recipe do? | `docs/src/recipes.md` |
| How do the two layers fit together? | `docs/src/architecture.md` |
| What goes wrong in bash, `just`, libvirt, and mdBook? | **`docs/src/scripts.md`** |
| What does the tenant answer, and which fields lie? | **`docs/src/palette-api.md`** |
| Which packs, which presets, which pod range? | `docs/src/cluster-profile.md` |
| A failure and its correction | `docs/src/troubleshooting.md` |
| How do I test a change? | `docs/src/tests.md` |
| Where does each file live? | `docs/src/directories.md` |
| What does a setting do? | `docs/src/settings.md` |
| Why is it built this way? | `docs/src/decisions.md` |

The two pages in bold text hold the facts that this file held before. Read
`scripts.md` before you change a script. Each condition on that page gives no
error message.

## Project rules

These are hard rules. They override convenience. `docs/src/rules.md` explains
each one.

1. **Every action is a recipe.** Do not run a single command manually. Do not
   tell the user to click a button in a web interface when a command can do the
   task. If a task has no recipe, add the recipe to the `justfile`. Then run
   it.
2. **Every create recipe has a remove recipe.** When you add `x-up`, add
   `x-down`. `scripts/lint-pairs.sh` fails the build on a create with no twin.
3. **Every recipe is idempotent.** Test the state, then act. If the object
   exists, call `skip` from `scripts/lib.sh` and return 0.
4. **Every recipe has a documentation comment.** `just` shows it as the help
   text. The LAST comment line before a recipe is the help text, so put an
   explanation above it and never after it.
5. **The documentation includes the source.** Never paste code into the book.
   Put an anchor in the file and `{{#include ../../path:anchor}}` it.

## Before you finish

```bash
just lint    # fmt, pairs, params, includes, shellcheck, test, tofu, book
just test    # the guards alone, offline, about a second
```

`just lint` is the check that must pass. There is no other.

**Add a test with a guard.** A guard is one `if` away from never firing again,
and when it stops it reports nothing: the recipe still returns 0 and the cost
arrives an hour later. `tests/*.test.sh` reach no libvirt, no tenant, and no
network, so a new one must not either. See `docs/src/tests.md`.

**Do not write a `trap ... EXIT` in a test file.** That trap prints the
totals. A second trap replaces it, and the file then reports nothing.

## Standing decisions

**Do not add Edge Native or CanvOS again.** Commit 2da762e removed them. There
is no prebuilt Edge installer ISO to download. Thus that method needs a local
CanvOS build, and CanvOS needs Docker. The agent-mode documentation tells you
not to install Docker on the host. This tooling uses Palette **agent mode**: the
host starts the standard Ubuntu cloud image, and cloud-init installs the agent.
See `docs/src/decisions.md`.

**Do not run `tofu` manually.** `scripts/cluster.sh` is the only caller. That
script computes the state path, the credentials, and the host list one time. A
`tofu` command outside that script writes the state to an incorrect
directory.

**Never print the token.** `just config` and `just preflight` print its length.
Keep it that way.

**Do not publish a measured time.** A number in a document is correct only for
the day of the measurement. The table in this file gave 646s for `cluster-up`.
An add-on profile then made that value two times larger, and no person changed
the table. `just ci-times` reads the pipeline, which measures the pinned
versions that the justfile holds now. Give the recipe, and not a number.

**Do not put a credential in the checkout.** The API key is a tenant
credential. It is at `~/.config/palette-edge-libvirt/api-key`. `api_key_file`
does not use `PEL_CONFIG_DIR`, because that variable can name a checkout. The
registration token belongs to one project, and it is in the environment file of
that project. `docs/src/project-layout.md` gives the reason for the two
locations.

## The shape of the repository

```
justfile        the only interface: configuration and thin recipes
scripts/*.sh    all logic. Input from the environment, so each runs alone
tests/          the offline suite. tests/assert.sh holds the assertions
templates/      network.xml, user-data.tmpl.yaml, project.env. @NAME@ markers
terraform/      the cluster layer, HCL only. cluster.sh is the only caller
docs/src/       the book. docs/gruvbox and docs/mermaid*.js are generated
```

Two layers, and each owns objects on **both** sides:

| Layer | Workstation | Palette | Recipes |
| --- | --- | --- | --- |
| infrastructure | network, pool, disks, VMs | host records | `infra-up` / `infra-down` |
| cluster | the OpenTofu state | profiles, cluster | `cluster-up` / `cluster-down` |

Registration is the connection between the two layers. `infra-up` does not
return until each host has the `ready` state in Palette. A machine that did not
register is not usable by the layer above. See `docs/src/architecture.md`.

`new-project` writes values into `templates/project.env`. That file also holds
the anchors that the book includes. **Change that file when you add a
setting.** If you do not, the book does not describe the new setting.

To run a script directly, set its environment:

```bash
PALETTE_EDGE_TOKEN=x scripts/seed-iso.sh test-1 ./seeds ./build
NETWORK=pe-net SUBNET=192.168.140 BUILD_DIR=./build scripts/net-up.sh
```

## What is verified

The two layers are verified against the live tenant on the Thelio, with 1
control node and 2 worker nodes. The recipes build the machines. Each host
registers. Palette reports `Running` with each condition true. The kubeconfig
operates. `cluster-verify` passes. The removal recipes empty the workstation and
the tenant. The add-on profile is verified in the same way, and `just dashboard`
opens Headlamp with no sign-in page.

Continuous integration is verified end to end on `qemu:///session`, with the
runner NOT in the `libvirt` group. The workstation and the tenant are both empty
after a run. `just ci-times` reports what it costs.

The pinned combination is in the `justfile`, which is the only record of it. Run
`just config` to see it, and `just palette-packs <name>` before you change one.

**Not verified**: more than one control plane node (`CONTROL_COUNT=3`, where
kube-vip must move the address). A new pack version on a cluster that operates.
`runner-setup-undo`: the recipe exists and `just lint` examines it, but no
person has run it.

## Prose

Write all prose in ASD-STE100 Simplified Technical English. This applies to the
book, the README, this file, the code comments, and the commit messages. Use
short sentences. Use the active voice. Use one idea in each sentence. Do not use
idioms or figures of speech.

**Write in man-page voice.** The reader deploys Kubernetes clusters. Do not
define a term that this reader knows. Do not describe what a command visibly
does. A heading and a command block are a complete section. Prose is for a
warning, a non-obvious consequence, or a link.

Test each sentence: **does it give an expert something that the command, the
heading, and their own knowledge do not?** If not, delete it. Do not write a
shorter replacement. Delete the line.

Example: the heading `## 0. Completions (optional)` needs no sentence below it.
The command block follows it. "The bash completion is optional. It gives the
recipe names and their arguments:" is the error.

Put a short fact in a comment on the command line, not in a sentence above it:

```bash
just host-setup   # libvirt, KVM, the tools, and the libvirt and kvm groups
```

A message that refuses an operation must name the correction. `set
no-exit-message` makes that message the only text that the user reads.
