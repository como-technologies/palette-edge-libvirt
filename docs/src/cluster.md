# Create the cluster

## 1. Build the layer

```bash
just cluster-up
```

The recipe makes three objects in Palette:

| Object | Name |
| --- | --- |
| infrastructure cluster profile | `<CLUSTER_NAME>-infra` |
| add-on cluster profile | `<CLUSTER_NAME>-addon` |
| cluster | `<CLUSTER_NAME>` |

`just infra-up` named each machine `<CLUSTER_NAME>-cp-<N>` or
`<CLUSTER_NAME>-wk-<N>`. The `cp` names go in the control plane pool, and the
`wk` names go in the worker pool. A libvirt domain and its Palette host have the
same name, so `just ls` and the Palette host list agree.

Palette then installs the four packs on every node. That takes about 11 minutes
for 1 control node and 2 workers. It installs the add-on profile after the
cluster answers, so Headlamp appears some minutes later than the nodes.

The recipe is idempotent, so a second run makes no new object. See
[The cluster profile](./cluster-profile.md) for each pack and each setting.

## 2. Watch the build

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

## 3. Use the cluster

```bash
just cluster-kubeconfig > ~/.kube/pe.yaml
KUBECONFIG=~/.kube/pe.yaml kubectl get nodes
```

The kubeconfig is a credential. The recipe prints it and writes no file, so you
choose the file and its mode.

## 4. Open the dashboard

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

To remove each object of the project, see [Remove everything](./teardown.md).
