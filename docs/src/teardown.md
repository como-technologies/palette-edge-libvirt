# Remove the lab

Every object that this repository creates has a recipe that removes it. See
[project rule 2](./rules.md#2-every-create-recipe-has-a-remove-recipe).

## Remove the virtual machines

```bash
just cluster-down
```

This recipe stops each `$LAB_NAME-*` domain, removes the definition, and deletes
the disk image. It keeps the network, the storage pool, and the installer ISO,
so the next `just cluster-up` is fast.

## Remove everything local

```bash
just nuke
```

`nuke` runs `cluster-down`, `infra-down`, and `seed-clean`. It keeps the
installer ISO, because that file takes a long time to download. To delete the
ISO too, run `just iso-clean`.

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
| Edge Hosts | Clusters > Edge Hosts |
| Cluster profile | Profiles |
| Registration token | Tenant Settings > Registration Tokens |

Delete the cluster first. Then deregister the edge hosts.

## Remove the secrets

Delete `.env` to remove your token and your API key from the workstation:

```bash
rm .env
```

`just seed-clean` deletes the seed ISO files, which also hold the token.

## What stays

`just pool-down` removes the storage pool definition. It keeps the disk image
files in `/var/lib/libvirt/images/$LAB_NAME`. Run `just cluster-down` first to
delete those files. `just pool-down` prints a warning if the directory still
holds a volume.
