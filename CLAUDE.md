# CLAUDE.md

Guidance for Claude Code when working in this repository.

**The book is the documentation, and this file is not a second copy of it.**
`docs/src/` holds every fact, with the error text and the correction, and
`just lint` tests it. Read the page before you change the thing it describes.
When you learn something new, put it in the book and leave this file alone.

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

The two in bold hold what used to be in this file. `scripts.md` is the one to
read before you edit a script: every trap on it is silent, and each one cost a
day.

## Project rules

These are hard rules. They override convenience. `docs/src/rules.md` explains
each one.

1. **Every action is a recipe.** Never run a one-off command, and never tell the
   user to click a button in a web interface when a command can do the task. If
   a task has no recipe, add the recipe to the `justfile` first, then run it.
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

**Never write a `trap ... EXIT` in a test file.** That trap prints the tally,
and a second one discards it silently.

## Standing decisions

**Do not reintroduce Edge Native or CanvOS.** It was tried and removed in
2da762e. There is no prebuilt Edge installer ISO to download, so that path needs
a local CanvOS build, and CanvOS needs Docker — which the agent-mode
documentation tells you not to install on the host. This tooling uses Palette
**agent mode**: the host boots the stock Ubuntu cloud image and cloud-init
installs the agent. See `docs/src/decisions.md`.

**Never run `tofu` by hand.** `scripts/cluster.sh` is the only caller. It
computes the state path, the credentials, and the host list one time and in one
way, and a `tofu` run outside it writes state to the wrong place.

**Never print the token.** `just config` and `just preflight` print its length.
Keep it that way.

**Never publish a measured time.** A number in a document is true of the day
somebody measured it: the table that used to be here said `cluster-up` took
646s, and an add-on profile doubled that without changing a word. `just
ci-times` reads the pipeline, which measures the pins that the justfile holds
now. Quote the recipe, never a number.

**Never put a credential in the checkout.** The API key is a tenant credential
and lives at `~/.config/palette-edge-libvirt/api-key`; `api_key_file` ignores
`PEL_CONFIG_DIR` on purpose, because that variable can name a checkout. The
registration token belongs to one project and lives in that project's
environment file. `docs/src/project-layout.md` says why they are apart.

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

The seam is registration: `infra-up` does not return until every host is `ready`
in Palette, because a machine that never registered is of no use to the layer
above. `docs/src/architecture.md` has the detail.

`templates/project.env` is the file that `new-project` fills in, and it carries
the anchors that the book includes. **Edit it when you add a setting**, or the
book goes stale.

To run a script directly, set its environment:

```bash
PALETTE_EDGE_TOKEN=x scripts/seed-iso.sh test-1 ./seeds ./build
NETWORK=pe-net SUBNET=192.168.140 BUILD_DIR=./build scripts/net-up.sh
```

## What is verified

Both layers, end to end, against the live tenant on the Thelio, 1 control and 2
workers: the machines build, every host registers, Palette reports `Running`
with every condition true, the kubeconfig works, `cluster-verify` passes, and
teardown empties both sides. The add-on profile is verified the same way, and
`just dashboard` opens Headlamp with no sign-in.

Continuous integration is verified end to end on `qemu:///session`, with the
runner NOT in the `libvirt` group. The workstation and the tenant are both empty
after a run. `just ci-times` reports what it costs.

The pinned combination is in the `justfile`, which is the only record of it. Run
`just config` to see it, and `just palette-packs <name>` before you change one.

**Still unverified**: more than one control-plane node (`CONTROL_COUNT=3`, where
kube-vip has to fail over), a pack re-pin on a running cluster, and
`runner-setup-undo` — the twin exists and is linted, and nothing has ever run it.

## Prose

The book, the README, and the code comments use ASD-STE100 Simplified Technical
English: short sentences, active voice, one idea in each. A message that refuses
must name the correction, because `set no-exit-message` makes it the only thing
the user sees.
