# Remove everything

Every object that this repository creates has a recipe that removes it. See
[project rule 2](./rules.md#2-every-create-recipe-has-a-remove-recipe).

Each layer removes what it made, on the workstation **and** in Palette. Remove
the layers from the top.

## Remove the cluster layer

```bash
just cluster-down
```

OpenTofu removes the cluster and the cluster profile. The hosts, the machines,
and the project all stay, so `just cluster-up` builds them again. A project that
has no cluster layer gets a skip.

The recipe leaves the state file in
`~/.local/state/palette-edge-libvirt/<project>/`. The file is then empty of
objects, and the next `cluster-up` fills it again.

## Remove the infrastructure layer

```bash
just infra-down
```

The recipe removes the Palette record of each host, then each
`$CLUSTER_NAME-*` domain and its disk, then the storage pool and the network.

It **refuses** while the project still holds a cluster. Palette keeps a cluster
whose machines are gone, and that cluster is then impossible to repair.

`just hosts-deregister` removes only the host records, and
`just host-deregister <host>` removes one. The machines stay in both cases.

## Remove everything of the project

```bash
just nuke
```

`nuke` runs `cluster-down` and then `infra-down`, so it removes the layers from
the top. It then removes the seed ISO files, the registration token, the Palette
project, and the environment file of the project. It asks you to type the
project name first, because the delete is not reversible. `FORCE=1` answers in
advance.

Three things stay, and none of them belongs to one project:

| Stays | Where | Remove it with |
| --- | --- | --- |
| The Ubuntu cloud image | `~/.cache/palette-edge-libvirt` | `just image-clean` |
| Your Palette API key | `~/.config/palette-edge-libvirt/api-key` | `just api-key-clear` |
| OpenTofu | `~/.local/bin/tofu` | `just tofu-uninstall` |

## Remove the packages

```bash
just host-setup-undo
```

This recipe removes the packages that `just host-setup` installed. It also
removes your user from the `libvirt` group and the `kvm` group.

## What stays after pool-down

`just pool-down` removes the storage pool definition. It keeps the disk image
files in `/var/lib/libvirt/images/$CLUSTER_NAME`. Run `just infra-down` first to
delete those files. `just pool-down` prints a warning if the directory still
holds a volume.
