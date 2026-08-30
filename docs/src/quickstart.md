# Create the lab

Complete [Prepare the workstation](./host-setup.md) and
[Configure the tenant](./configuration.md) first.

## 1. Configure the tenant

```bash
just api-key-set            # one time for the workstation
just new-project pe-thelio  # the project, its token, and its file
```

See [Configure the tenant](./configuration.md). To work on a project that
already has a file, select it instead:

```bash
just projects                  # the projects that have a file
just default-project pe-thelio
```

`just palette-projects` lists the projects in your tenant and marks the one that
`PALETTE_PROJECT` names. A wrong project name gives no error at boot time: the
host starts, the agent runs, and the host never shows in Palette.

## 2. Create the lab

```bash
just cluster-up
```

This recipe and its partner recipes are:

```just
{{#include ../../justfile:clusterup}}
```

`cluster-up` runs `preflight`, `infra-up`, and `image-fetch` first. Each of
those recipes is idempotent, so a second run of `cluster-up` changes nothing.

## What happens

1. `preflight` tests the workstation and your `.env` values.
2. `infra-up` creates the `pe-net` network and the `pe-pool` storage pool.
3. `image-fetch` downloads the stock Ubuntu cloud image and tests its checksum.
   The download runs one time.
4. For each host, `seed` builds a CIDATA ISO with your token.
5. For each host, `host-up` copies the cloud image, grows the copy, and starts
   the virtual machine.

The hosts start in seconds. The agent installation then takes some minutes,
because cloud-init installs packages first.

## 3. Watch the progress

```bash
just ls                      # every host with its state and address
just host-status pe-cp-1     # the progress of one host
just console pe-cp-1         # the serial console, ctrl-] to exit
```

The console shows the cloud-init output. To log in, use the user `ubuntu` and
the password from `HOST_PASSWORD` in `.env`.

## 4. Confirm the registration

```bash
just palette-hosts
```

The recipe lists the hosts that registered with your project. Each host uses the
same name as the libvirt domain, for example `pe-cp-1`.

If a host does not show after ten minutes, see
[Troubleshooting](./troubleshooting.md).

## 5. Remove the seed

After a host registers, remove the seed ISO from it:

```bash
just host-eject pe-cp-1
```

The seed ISO holds your registration token. An ejected host keeps no copy.

## 6. Make the cluster

Palette makes the cluster from the registered hosts. In Palette:

1. Make a cluster profile. Select **Palette eXtended Kubernetes - Edge
   (PXK-E)** for the Kubernetes layer. Add the CNI, the CSI, and the add-ons to
   test.
2. Make a cluster. Select the profile. Assign the registered hosts to the
   control plane pool and the worker pool.
3. Wait for the deployment. Palette shows the progress for each pack.

`PALETTE_VIP_SKIP=true` in `.env` gives a lab with one control plane node. For
more than one control plane node, set the value to `false`, rebuild the seeds,
and give a VIP in Palette. Use a free address of the lab subnet, for example
`192.168.140.10`. See [The lab network](./network.md#address-plan).

## Run a second combination

The operating system image does not change between tests. Change the cluster
profile in Palette and deploy again.

To change the host size or the host count, edit `.env` and rebuild:

```bash
just cluster-down
just cluster-up
```
