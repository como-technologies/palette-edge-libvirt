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
| `-install` | Install a tool for your user. |
| `-uninstall` | Remove a tool that `-install` put there. |
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

## The two layers

The tooling builds a cluster in two layers. Each layer owns objects on the
workstation **and** in Palette, and each layer removes everything that it made.

| Layer | On the workstation | In Palette |
| --- | --- | --- |
| Infrastructure | network, storage pool, disks, virtual machines | the host record of each machine |
| Cluster | the OpenTofu state | the cluster profile and the cluster |

### The infrastructure layer

```just
{{#include ../../justfile:infraup}}
```

`infra-up` is idempotent, and each recipe that it depends on is idempotent, so a
second run makes no new object. It does five things:

1. `preflight` tests the workstation and your values.
2. `net-up` and `pool-up` make the network and the storage pool. `CLUSTER_NAME`
   gives both names.
3. `image-fetch` downloads the stock Ubuntu cloud image and tests its checksum.
   The download runs one time.
4. For each host, `seed` builds a CIDATA ISO with your token, and `host-up`
   copies the cloud image, grows the copy, and starts the virtual machine.
5. `hosts-wait` waits until every host registers with Palette.

Step 5 is the seam. A virtual machine that did not register is of no use to the
cluster layer, so the layer is not complete until the record exists. The wait
takes some minutes, and `REGISTER_TIMEOUT` gives up after 900 seconds.

`infra-down` reverses all of it, including the host records. It refuses while
the cluster layer exists, because Palette keeps a cluster whose machines are
gone and that cluster is then impossible to repair.

### The cluster layer

```just
{{#include ../../justfile:clusterup}}
```

OpenTofu builds this layer, and `scripts/cluster.sh` is the one caller. The
recipes make two objects in Palette: the cluster profile `<CLUSTER_NAME>-infra`,
and the cluster `<CLUSTER_NAME>` on the hosts that the layer below registered.

The state file names both objects, and it lives in
`~/.local/state/palette-edge-libvirt/<project>/`. It is never in the checkout:
lose it and Palette holds a cluster that no recipe can remove.

`cluster-down` removes both objects. The hosts and the machines stay, so
`cluster-up` builds them again. See [Create the cluster](./cluster.md).

### Everything

```just
{{#include ../../justfile:nuke}}
```

`nuke` removes every object of the project: both layers, the seeds, the
registration token, the Palette project, and the environment file. The cloud
image and the API key stay, because neither belongs to one project. See
[Remove everything](./teardown.md).

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
