# Create the lab

Complete [Prepare the workstation](./host-setup.md) and
[Configure the tenant](./configuration.md) first.

## One command

```bash
just cluster-up
```

This recipe and its partner recipes are:

```just
{{#include ../../justfile:clusterup}}
```

`cluster-up` runs `preflight`, `infra-up`, and `iso-fetch` before it makes the
virtual machines. Each of those recipes is idempotent, so a second run of
`cluster-up` changes nothing.

## What happens

1. `preflight` tests the workstation and your `.env` values.
2. `infra-up` creates the `pe-net` network and the `pe-pool` storage pool.
3. `iso-fetch` downloads the installer ISO. The download runs one time.
4. For each node, `seed` builds a CIDATA ISO with your token.
5. For each node, `host-up` creates the virtual machine and starts it.

The first `iso-fetch` takes several minutes. The download goes to `iso/`, so
later runs use the cached file.

## Watch the installation

```bash
just console pe-cp-1
```

Press `ctrl-]` to leave the console. The installation takes a few minutes for
each host. To see the state of all hosts:

```bash
just ls
```

## Confirm the registration

Open Palette. Go to **Clusters**, then **Edge Hosts**. Each host shows with the
same name as the libvirt domain, for example `pe-cp-1`.

If a host does not show, see [Troubleshooting](./troubleshooting.md).

## Remove the installer media

After the installation is complete, remove both ISO files from the host:

```bash
just host-eject pe-cp-1
```

The seed ISO holds your registration token. An ejected host keeps no copy of the
token.

## Make the cluster

Palette makes the cluster from the registered hosts. In Palette:

1. Make a cluster profile of the type **Edge Native**. Select the operating
   system, the Kubernetes version, the CNI, and the CSI to test.
2. Make a cluster. Select the profile. Assign the registered edge hosts to the
   control plane pool and the worker pool.
3. Wait for the deployment. Palette shows the progress for each pack.

## Run a second combination

Change the profile in Palette and deploy again. To test a different node size or
node count, change `.env` and rebuild:

```bash
just cluster-down
just cluster-up
```
