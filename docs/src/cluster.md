# Create the cluster

This is layer 2. `just infra-up` does not return until every host registers, so
the layer below is ready when this page starts.

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

The recipe makes three objects in Palette:

| Object | Name |
| --- | --- |
| infrastructure cluster profile | `<CLUSTER_NAME>-infra` |
| add-on cluster profile | `<CLUSTER_NAME>-addon` |
| cluster | `<CLUSTER_NAME>` |

The control plane pool takes the `-cp-` hosts and the worker pool takes the
`-wk-` hosts. The libvirt domain name and the Palette host name are the same, so
`just ls` and the Palette host list agree.

Palette then installs the four packs on every node. That takes about 11 minutes
for 1 control node and 2 workers. It installs the add-on profile after the
cluster answers, so Headlamp appears some minutes later than the nodes.

The recipe is idempotent, so a second run makes no new object. See
[The cluster profile](./cluster-profile.md) for each pack and each setting.

## 4. Watch the build

```bash
just palette-clusters   # the state, the uid, the endpoint, and both profiles
just cluster-show       # the ids, and a link to the cluster in the console
```

The two answer the same question from two places, and that difference matters:

| Recipe | Reads | Knows about |
| --- | --- | --- |
| `just palette-clusters` | Palette | every cluster of the project, whatever built it |
| `just cluster-show` | the OpenTofu state | the cluster that this checkout built |

Use `palette-clusters` for the uid of a cluster that this checkout did not
build, or after the state is gone. The uid is also what names the cluster in
the console URL and in the `server:` line of `just cluster-kubeconfig`.

The Palette console shows the progress of each pack. If the build fails, see
[The cluster builds for an hour and then fails](./troubleshooting.md#the-cluster-builds-for-an-hour-and-then-fails).

## 5. Use the cluster

```bash
just cluster-kubeconfig > ~/.kube/pe.yaml
KUBECONFIG=~/.kube/pe.yaml kubectl get nodes
```

The kubeconfig is a credential. The recipe prints it and writes no file, so you
choose the file and its mode.

## 6. Open the dashboard

```bash
just dashboard
```

The add-on profile installs Headlamp, the Kubernetes web interface. Its service
is a ClusterIP, so the recipe carries the connection through the API server and
opens `https://localhost:8443`. There is no sign-in: the profile sets
`unsafeUseServiceAccountToken` in the pack values, so the port forward is what
guards the page, and that forward needs the administrator kubeconfig.
`DASHBOARD_PORT` takes a different local port. Press ctrl-c to close it.

See [The add-on profile](./cluster-profile.md#the-add-on-profile).

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
[Settings](./settings.md#the-cluster-size).

## Remove the cluster

```bash
just cluster-down
```

This removes the cluster and both cluster profiles. The hosts, the machines, and
the project all stay, so `just cluster-up` builds them again.

Run it before `just infra-down`. That recipe refuses while the project holds a
cluster, because a cluster whose machines are gone is impossible to repair.

To remove each object of the project, see [Remove everything](./teardown.md).
