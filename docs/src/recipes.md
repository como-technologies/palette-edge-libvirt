# Recipes

The `justfile` is the only interface to this repository. To see every recipe and
its help text, run:

```bash
just
```

**This book holds no list of the recipes.** The output of `just` is always
correct for the checkout that you have. A table here would be correct on the day
someone writes it and wrong after the next rename. See
[project rule 5](./rules.md#5-the-documentation-includes-the-source).

## The naming pattern

| Suffix or prefix | Meaning |
| --- | --- |
| `-up` | Create the object and start it. |
| `-down` | Stop the object and remove it. |
| `-fetch` | Download a file into a cache. |
| `-clean` | Delete generated files. |
| `-status` | Report progress. Makes no change. |
| `-undo` | Reverse a recipe that changes the workstation. |
| `new-` | Create an object in your Palette tenant. |
| `remove-` | Delete an object from your Palette tenant. |

A recipe with no suffix reports information, for example `config`, `ls`, `ip`,
`projects`, and `preflight`.

`scripts/lint-pairs.sh` reads these shapes. A new recipe that creates something
and has no partner stops `just lint`:

```bash
{{#include ../../scripts/lint-pairs.sh:pairs}}
```

## Recipes with arguments

```bash
just new-project iris "A description"
just default-project iris
just host-up <host>             # role defaults to worker
just host-up <host> control     # control plane size
just seed <host>
just console <host>
```

## Bash completion

The completion completes the recipe names, and it completes the arguments: the
host names, the roles `control` and `worker`, and the project names.

For the current shell:

```bash
source <(just bash-completion)
```

For every shell, choose one:

```bash
just bash-completion-install          # writes a file for your user
just bash-completion >> ~/.bashrc     # writes the script into your .bashrc
```

`bash-completion-install` prints the path of the file, so this also works:

```bash
source "$(just bash-completion-install)"
```

`just bash-completion-uninstall` removes the installed file.

The completion binds to the `just` command, so bash uses it for every project.
This is safe. It completes the recipe names of any justfile, and it completes
the arguments only in this checkout. In another project the argument completion
gives nothing.

### The completion holds no list of recipes

`just` is the source. The completion reads the recipe names from
`just --summary` and the parameters from `just --dump --dump-format json`. A
new recipe therefore completes with no change to the completion.

This works because a parameter takes its name from the **kind** of value it
holds, not from its position:

```bash
{{#include ../../scripts/bash-completion.sh:kinds}}
```

`just host-up host role="worker"` has the parameters `host` and `role`, so the
completion offers the node names and then `control worker`. A new recipe
`host-restart host` offers the node names with no edit.

`just lint` runs `scripts/lint-params.sh`. That test reads the kinds from the
completion and the parameters from `just`. A parameter with an unknown name
stops the build, which is the moment to add the kind or to name the parameter
as free text.

## The cluster recipes

```just
{{#include ../../justfile:clusterup}}
```

`cluster-up` makes the whole lab. It runs `preflight`, `infra-up`, and
`image-fetch` first, and each of those is idempotent, so a second run of
`cluster-up` makes no new object.

The recipe does five things:

1. `preflight` tests the workstation and your values.
2. `infra-up` makes the lab network and the storage pool. `LAB_NAME` gives both
   names.
3. `image-fetch` downloads the stock Ubuntu cloud image and tests its checksum.
   The download runs one time.
4. For each host, `seed` builds a CIDATA ISO with your token.
5. For each host, `host-up` copies the cloud image, grows the copy, and starts
   the virtual machine.

`cluster-down` removes the virtual machines and keeps the network, the pool,
and the image, so the next `cluster-up` is fast. `nuke` also removes the
network, the pool, and the seeds.

Neither recipe touches Palette. The hosts stay registered, so `nuke` reports the
records that stay and names `just cluster-deregister`, which removes them. That
recipe is the only one that deletes a host record. See
[Remove the lab](./teardown.md).

## The layers

The `justfile` holds the configuration and thin recipes. Each recipe with logic
calls a script in `scripts/`, and the recipe passes the values in the
environment. This keeps the `justfile` readable, and it lets `shellcheck` test
the logic.

To see what one script does, read the comment at the top of it. Every script
carries its purpose, its inputs, and a note on how it stays idempotent:

```bash
head -20 scripts/host-up.sh
```

`scripts/lib.sh` holds the shared functions. `scripts/palette-lib.sh` holds the
functions for the Palette API. Both are sourced, never executed.

## Quality

```bash
just fmt    # format the justfile
just lint   # test the format, the pairs, the scripts, and the docs build
```

`just lint` runs five tests:

1. `just --fmt --check` tests the format of the `justfile`.
2. `scripts/lint-pairs.sh` tests
   [project rule 2](./rules.md#2-every-create-recipe-has-a-remove-recipe).
3. `scripts/lint-params.sh` tests that the completion knows every recipe
   parameter.
4. `shellcheck` tests every script.
5. `mdbook build` builds the book, which tests every include path and every
   anchor.

The GitHub Actions workflow runs `just lint` on each push and each pull request.
