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

## Remove the packages

```bash
just host-setup-undo
```

This recipe removes the packages that `just host-setup` installed. It also
removes your user from the `libvirt` group and the `kvm` group.

## Remove the Palette objects

The recipes control the workstation only. Palette keeps its own objects. Remove
these in Palette:

| Object | Location in Palette |
| --- | --- |
| Cluster | Clusters |
| Registered hosts | `just host-deregister <host>` |
| Cluster profile | Profiles |
| Registration token | Tenant Settings > Registration Tokens |

Delete the cluster first. Then deregister each host. `just palette-hosts` lists
the hosts that are still registered, and `just host-deregister <host>` removes
one record. See [Make the cluster](./cluster.md#remove-the-cluster).

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
