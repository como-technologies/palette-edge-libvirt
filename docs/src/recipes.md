# Recipes

The `justfile` is the only interface to this repository. To see every recipe and
its help text, run:

```bash
just
```

This book does not hold a copy of that list. See
[project rule 5](./rules.md#5-the-documentation-includes-the-source). The output
of `just` is always correct for the checkout that you have.

## The naming pattern

| Suffix | Meaning |
| --- | --- |
| `-up` | Create the object and start it. |
| `-down` | Stop the object and remove it. |
| `-fetch` | Download a file into a cache. |
| `-status` | Report progress. Makes no change. |
| `-clean` | Delete generated files. |
| `-undo` | Reverse a recipe that changes the workstation. |

A recipe with no suffix reports information, for example `config`, `ls`, `ip`,
and `preflight`.

## Groups

| Group | Recipes |
| --- | --- |
| Meta | `default`, `config`, `preflight` |
| Host packages | `host-setup`, `host-setup-undo` |
| Infrastructure | `infra-up`, `infra-down`, `net-up`, `net-down`, `pool-up`, `pool-down` |
| Host image | `image-fetch`, `image-clean` |
| Seeds | `seed`, `seed-all`, `seed-clean` |
| Hosts | `host-up`, `host-down`, `host-status`, `host-eject`, `console`, `ip`, `ls` |
| Projects | `projects`, `new-project`, `remove-project`, `default-project`, `adopt-project`, `unadopt-project` |
| Palette | `palette-projects`, `palette-hosts` |
| Cluster | `cluster-up`, `cluster-down`, `nuke` |
| Docs | `docs`, `docs-serve`, `docs-clean`, `docs-theme`, `docs-theme-clean` |
| Quality | `fmt`, `lint` |

## Recipes with arguments

```bash
just new-project iris "A nice description"
just default-project iris
just remove-project iris
just host-up pe-wk-3            # role defaults to worker
just host-up pe-cp-2 control    # control plane size
just seed pe-wk-3
just host-down pe-wk-3
just console pe-cp-1
just ip pe-cp-1
```

## The scripts

Each recipe with logic calls a script in `scripts/`. The recipe passes values in
the environment. This keeps the `justfile` readable, and it lets `shellcheck`
test the logic.

| Script | Function |
| --- | --- |
| `lib.sh` | Shared functions. Other scripts source it. |
| `preflight.sh` | Test the tools, the permissions, and the capacity. |
| `config.sh` | Print the effective configuration. |
| `net-up.sh`, `net-down.sh` | Manage the lab network. |
| `pool-up.sh`, `pool-down.sh` | Manage the storage pool. |
| `image-fetch.sh` | Download the cloud image and test its checksum. |
| `seed-iso.sh` | Build one CIDATA seed ISO. |
| `host-up.sh`, `host-down.sh`, `host-eject.sh` | Manage one virtual machine. |
| `host-ip.sh`, `lab-ls.sh`, `host-status.sh` | Report the host state. |
| `palette-lib.sh` | Shared Palette API functions. Other scripts source it. |
| `palette-api.sh` | Read the tenant through the Palette API. |
| `project-*.sh` | Make, remove, list, and select a project. |
| `cluster-down.sh` | Remove every host in the lab. |
| `for-each-node.sh` | Run a command for each node name. |
| `lint-shell.sh` | Run `shellcheck` on every script. |

## Quality

```bash
just fmt    # format the justfile
just lint   # test the format, the scripts, and the docs build
```

`just lint` runs three tests. It tests the `justfile` format. It runs
`shellcheck` on every script. It builds the book, which also tests every
include path and every anchor.

The GitHub Actions workflow runs `just lint` on each push and each pull request.
