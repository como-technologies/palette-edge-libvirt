# Remove the lab

Every object that this repository creates has a recipe that removes it. See
[project rule 2](./rules.md#2-every-create-recipe-has-a-remove-recipe).

## Remove the virtual machines

```bash
just cluster-down
```

This recipe stops each `$LAB_NAME-*` domain, removes the definition, and deletes
the disk image. It keeps the network, the storage pool, and the cloud image, so
the next `just cluster-up` is fast.

## Remove everything local

```bash
just nuke
```

`nuke` runs `cluster-down`, `infra-down`, and `seed-clean`. It keeps the Ubuntu
cloud image, because that file takes a long time to download. To delete the
image too, run `just image-clean`.

**`nuke` changes no object in Palette.** Each of the three recipes operates on
libvirt, so the hosts stay registered and the console still shows them. A recipe
that removes a virtual machine must not delete a tenant record without a word.
The recipe prints the hosts that stay, and names the recipe below.

## Remove the packages

```bash
just host-setup-undo
```

This recipe removes the packages that `just host-setup` installed. It also
removes your user from the `libvirt` group and the `kvm` group.

## Remove the Palette objects

The recipes control the workstation only. Palette keeps its own objects. Remove
these in Palette:

| Object | How to remove it |
| --- | --- |
| Cluster | In Palette, at **Clusters**. |
| Cluster profile | In Palette, at **Profiles**. |
| Registered hosts | `just cluster-deregister`, or one at a time with `just host-deregister <host>`. |
| Registration token | `just remove-project <project>` deletes it with the project. |

Delete the cluster first, then the profile. Then remove the host records:

```bash
just palette-hosts       # the hosts that are still registered
just cluster-deregister  # remove every record of this lab
```

`cluster-deregister` takes its scope from the environment file of the default
project. It reads the hosts of `PALETTE_PROJECT` only, and it removes the record
of each name that starts with `$LAB_NAME-`. It is idempotent, and it leaves the
virtual machines as they are.

A project holds one lab, so the prefix normally keeps every host. It keeps
fewer after you change `LAB_NAME`, because a host that registered under the old
name keeps the old name. The recipe names each host that it does not touch, and
`just host-deregister <host>` removes one of those. See
[Create the cluster](./cluster.md#remove-the-cluster).

## Remove the secrets

`just remove-project <project>` deletes the environment file that holds your
registration token. `just seed-clean` deletes the seed ISO files, which also
hold the token. `just api-key-clear` deletes the API key.

The files are outside the checkout, so `rm -rf` on the checkout removes none of
them. See [The lab directories](./directories.md).

## What stays

`just pool-down` removes the storage pool definition. It keeps the disk image
files in `/var/lib/libvirt/images/$LAB_NAME`. Run `just cluster-down` first to
delete those files. `just pool-down` prints a warning if the directory still
holds a volume.
