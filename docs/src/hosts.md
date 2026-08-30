# Create the hosts

This page creates the virtual machines and registers them with your Palette
project. It makes no cluster. [Make the cluster](./cluster.md) is the next step.

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

## Change the host size or the host count

Edit the project file, then build the lab again:

```bash
just cluster-down
just cluster-up
```

[Settings](./settings.md#the-lab-size) describes those values.

## Next

Every host is registered and idle. [Make the cluster](./cluster.md).

## More

[Architecture](./architecture.md) describes what the recipes build, and where
each part of the state lives.
[Host registration](./edge-hosts.md) describes the seed ISO, the agent
installation, and how to remove a host or rotate the token.
[The lab network](./network.md) describes the network definition and the
address plan.
