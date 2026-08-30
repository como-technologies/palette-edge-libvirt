# Create the lab

Complete these three pages first:

1. [Prepare the workstation](./host-setup.md)
2. [Configure the tenant](./configuration.md)
3. [Projects](./projects.md)

`just config` shows the project that the recipes operate on now.

## 1. Create the lab

```bash
just cluster-up
```

The hosts start in seconds. The agent installation then takes some minutes,
because cloud-init installs the packages first.

The recipe is idempotent, so a second run changes nothing. See
[The cluster recipes](./recipes.md#the-cluster-recipes) for what it does.

## 2. Watch the progress

```bash
just ls                 # every host with its state and address
just host-status <host> # the progress of one host
just console <host>     # the serial console, ctrl-] to exit
```

The console shows the cloud-init output. To log in, use the user `ubuntu` and
the password from `HOST_PASSWORD`.

## 3. Confirm the registration

```bash
just palette-hosts
```

The recipe lists the hosts that registered with your project. Each host uses the
same name as the libvirt domain.

If a host does not show after ten minutes, see
[Troubleshooting](./troubleshooting.md#a-host-does-not-show-in-palette).

## 4. Remove the seed

After a host registers, remove the seed ISO from it:

```bash
just host-eject <host>
```

The seed ISO holds your registration token. An ejected host keeps no copy.

## 5. Make the cluster

Palette makes the cluster from the registered hosts. In Palette:

1. Make a cluster profile. Select **Palette eXtended Kubernetes - Edge
   (PXK-E)** for the Kubernetes layer. Add the CNI, the CSI, and the add-ons to
   test.
2. Make a cluster. Select the profile. Assign the registered hosts to the
   control plane pool and the worker pool.
3. Wait for the deployment. Palette shows the progress for each pack.

A lab with one control plane node needs no virtual address. For more than one
control plane node, set `PALETTE_VIP_SKIP` to `false`, build the seeds again,
and give a VIP in Palette. Use a free address of the lab subnet. See
[The lab network](./network.md#address-plan).

## Run a second combination

The operating system image does not change between tests. Change the cluster
profile in Palette and deploy again.

To change the host size or the host count, edit `envs/<project>.env` and build
the lab again:

```bash
just cluster-down
just cluster-up
```

[Settings](./settings.md#the-lab-size) describes those values.
