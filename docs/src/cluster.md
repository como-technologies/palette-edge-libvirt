# Create the cluster

This page builds the cluster layer: the cluster profile and the cluster, both in
Palette. OpenTofu makes them from the hosts that the layer below registered.

This is layer 2. Complete [Create the machines](./machines.md) first —
`just infra-up` does not return until every host registers, so the layer below
is ready when it does.

## 1. Install OpenTofu

```bash
just tofu-install
```

Ubuntu does not package OpenTofu. The recipe puts the pinned release in
`~/.local/bin`, and it needs no root. Do this one time for each workstation.

## 2. See the changes

```bash
just cluster-plan
```

The recipe prints what `cluster-up` would make, and changes nothing. It also
tests your settings, so a wrong value stops here.

## 3. Build the layer

```bash
just cluster-up
```

The recipe makes two objects in Palette:

| Object | Name |
| --- | --- |
| cluster profile | `<CLUSTER_NAME>-infra` |
| cluster | `<CLUSTER_NAME>` |

The control plane pool takes the `-cp-` hosts and the worker pool takes the
`-wk-` hosts. The libvirt domain name and the Palette host name are the same, so
`just ls` and the Palette host list agree.

Palette then installs the four packs on every node. That takes about 11 minutes
for 1 control node and 2 workers.

The recipe is idempotent, so a second run makes no new object. See
[The cluster profile](./cluster-profile.md) for each pack and each setting.

## 4. Watch the build

```bash
just palette-clusters   # the state and the health of the cluster
just cluster-show       # the ids, and a link to the cluster in the console
```

The Palette console shows the progress of each pack. If the build fails, see
[The cluster builds for an hour and then fails](./troubleshooting.md#the-cluster-builds-for-an-hour-and-then-fails).

## 5. Use the cluster

```bash
just cluster-kubeconfig > ~/.kube/pe.yaml
KUBECONFIG=~/.kube/pe.yaml kubectl get nodes
```

The kubeconfig is a credential. The recipe prints it and writes no file, so you
choose the file and its mode.

## Change the combination

Change a pack version in the project file, then build the layer again:

```bash
just cluster-plan
just cluster-up
```

Palette replaces that layer on the running cluster. The hosts stay as they are.
`just palette-packs <name>` lists the versions that the public registry offers.
[Settings](./settings.md#the-cluster-layer) describes each value.

To change the hosts themselves, see
[Create the hosts](./machines.md#change-the-machines).

## Remove the cluster

```bash
just cluster-down
```

This removes the cluster and the cluster profile. The hosts, the machines, and
the project all stay, so `just cluster-up` builds them again.

Run it before `just infra-down`. That recipe refuses while the project holds a
cluster, because a cluster whose machines are gone is impossible to repair.

## Next

The cluster is up. [Remove everything](./teardown.md) describes the way back
down.

## More

[The cluster profile](./cluster-profile.md) describes the four packs, the
virtual address, and where OpenTofu keeps its state.
[Settings](./settings.md#the-cluster-layer) describes every value of this layer.
[Architecture](./architecture.md) describes the two layers and the seam between
them.
