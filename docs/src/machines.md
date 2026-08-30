# Create the machines

This page builds the infrastructure layer: the network, the storage pool, the
virtual machines, and the host record of each machine in Palette. It makes no
Kubernetes cluster. [Create the cluster](./cluster.md) is the next step.

Complete these three pages first:

1. [Prepare the workstation](./host-setup.md)
2. [Configure the tenant](./tenant.md)
3. [Create a project](./project.md)

`just config` shows the project that the recipes operate on now.

## 1. Build the layer

```bash
just infra-up
```

The recipe makes the network and the pool, downloads the cloud image, builds one
seed ISO for each host, starts each virtual machine, and then **waits** until
every host registers with Palette.

The wait takes some minutes. Each host boots, cloud-init installs the agent, and
the host restarts one time. The recipe prints the count while it waits:

```text
    120s  1 of 3 registered, waiting for: theliolab-wk-1 theliolab-wk-2
```

The recipe is idempotent, so a second run makes no new object. See
[The two layers](./recipes.md#the-two-layers) for each step.

## 2. Watch one host

The wait tells you the count. To watch one host while it installs:

```bash
just ls                 # every host with its state and address
just host-status <host> # the progress of one host
just console <host>     # the serial console, ctrl-] to exit
```

The console shows the cloud-init output. To log in, use the user `ubuntu` and
the password from `HOST_PASSWORD`.

If the wait stops with a timeout, see
[Troubleshooting](./troubleshooting.md#a-host-does-not-show-in-palette).

## 3. Remove the seeds

After the hosts register, remove the seed ISO from each one:

```bash
just host-eject <host>
```

The seed ISO holds your registration token. An ejected host keeps no copy.

## Change the machines

Edit the project file, then build the layer again:

```bash
just infra-down
just infra-up
```

`CONTROL_COUNT`, `WORKER_COUNT`, and the size of each role live in the project
file. [Settings](./settings.md#the-cluster-size) describes them.

Virtual machines are cheap, and the tooling ties a host to one cluster. Build
them again rather than change one in place.

## Next

Every host is registered and idle. [Create the cluster](./cluster.md).

## More

[Architecture](./architecture.md) describes the two layers, and where each part
of the state lives.
[Host registration](./edge-hosts.md) describes the seed ISO, the agent
installation, and how to remove a host or rotate the token.
[The cluster network](./network.md) describes the network definition and the
address plan.
