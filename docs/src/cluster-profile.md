# The cluster profile

The cluster profile is the combination under test. The cluster exists to give it
hosts. OpenTofu makes both, and `scripts/cluster.sh` is the only caller.

For the commands, see [Create the cluster](./cluster.md).

## The four layers

Every pack comes from the Palette public registry, and every version is pinned
in the project file:

| Layer | Pack | Purpose |
| --- | --- | --- |
| os | `edge-native-byoi` | BYOOS (Edge), Agent Mode preset |
| k8s | `edge-k8s` | Palette eXtended Kubernetes - Edge (PXK-E) |
| cni | `cni-calico` | verified with Ubuntu and PXK-E |
| csi | `csi-local-path-provisioner` | a storage class that needs no hardware |

```hcl
{{#include ../../terraform/cluster-profile.tf:packs}}
```

`cloud = ["edge-native"]` keeps each lookup inside the Edge Native packs. Names
such as `cni-calico` exist for several infrastructure providers, and a pack for
the wrong provider is rejected only when Palette builds the profile.

To see the versions that a pack offers now:

```bash
just palette-packs edge-k8s
just palette-packs cni-calico
```

## Why the OS layer is different

The BYOOS pack has two presets. The default is **Appliance Mode**, and that mode
needs `options.system.uri` to name a Kairos provider image that CanvOS builds.
This repository builds no image: each host boots the stock Ubuntu cloud image
and cloud-init installs the Palette agent. See
[Design decisions](./decisions.md#agent-mode-not-edge-native).

**Agent Mode** is the preset that matches, and
`terraform/values/edge-native-byoi.yaml` selects it. That file is the one place
in the profile that does not take the default values of its pack, so it carries
the reason for each change.

A pinned version and vendored values can disagree. The profile therefore fails
the plan when the header of the values file names a different version:

```hcl
{{#include ../../terraform/cluster-profile.tf:profile}}
```

## The pod range

The `edge-k8s` pack gives the pods `192.168.0.0/16` and the services
`192.169.0.0/16`. The pod range is a problem here, and the service range is not:

- `just new-project` allocates a cluster subnet between `192.168.140.0/24` and
  `192.168.199.0/24`. Every one of them is inside `192.168.0.0/16`.
- Most home and office networks are inside it too.

Calico gives no NAT to a destination inside its own pool. A pod that asks
`192.168.140.1` for DNS therefore sends a packet from a pod address, the gateway
of the cluster network drops it, and every name stays unresolved. The cluster
comes up, `kubectl get nodes` reports three ready nodes, and Palette then waits
for a management agent that cannot reach `api.spectrocloud.com`.

`POD_CIDR` replaces that one line of the pack values:

```hcl
{{#include ../../terraform/cluster-profile.tf:podcidr}}
```

`replace` keeps every other default of the pack, so a new pack version needs no
new copy of 391 lines. A `replace` that matches nothing changes nothing and
reports nothing, so the profile also holds a precondition on the string that it
looks for.

Give `POD_CIDR` a range that holds neither `CLUSTER_SUBNET` nor the address of
your workstation. The default `10.244.0.0/16` does both. `just cluster-up` tests
the first of those before it makes anything.

## The virtual address

Palette refuses a cluster that gives no control plane endpoint. It refuses one
control plane node as firmly as three, and it answers:

```text
Parameter 'Host endpoint' should not be empty
```

`CLUSTER_VIP` is that address, and kube-vip on the hosts claims it. Two settings
must therefore agree, and they live in two different layers:

| Setting | Layer | Meaning |
| --- | --- | --- |
| `PALETTE_VIP_SKIP=false` | the seed ISO, layer 1 | the agent installs kube-vip |
| `CLUSTER_VIP` | the cluster, layer 2 | the address that kube-vip claims |

`just new-project` writes the `.10` address of the subnet that it allocated. That
address is below the DHCP pool, so no host can take it. See
[The cluster network](./network.md#address-plan).

A host whose seed skipped kube-vip registers correctly and leaves the address
unanswered, and the cluster then fails a long time later. `just cluster-up`
tests the pair first and stops with the correction. To change the seeds, build
the machines again:

```bash
just seed-clean
just infra-down
just infra-up
```

## The hosts

The topology gives the names, and the tooling gives the libvirt domain and the
Palette host the same one. OpenTofu therefore needs no list: it reads one
appliance for each name of the topology.

```hcl
{{#include ../../terraform/cluster.tf:appliances}}
```

The lookup is also the test. A name that never registered stops the plan with
that name in the message, and no cluster waits for a host that does not exist.

## Where the state lives

```text
~/.local/state/palette-edge-libvirt/<project>/terraform.tfstate
```

The state is the only record that connects the two objects in Palette to this
checkout. Lose it and Palette holds a cluster that no recipe can remove. It is
therefore not in the checkout, not in the module, and not in the current
directory. `just config` prints the path, and `PEL_STATE_DIR` moves it.

One project gets one state file, so a second project builds its own cluster and
neither one can destroy the objects of the other.

A backend block takes no variable, so the path cannot be in the module:

```hcl
{{#include ../../terraform/versions.tf:backend}}
```

The state holds the administrator kubeconfig of the cluster, so the directory is
mode 0700 and the state file is mode 0600. The API key is never in it: the
provider reads the key from the environment, and no variable carries it.

`just remove-project` deletes the state directory with the project. It refuses
while the state still names an object, because that record is the only way back
to the objects in Palette.

## The module

```text
terraform/versions.tf          the pins, and the local backend
terraform/providers.tf         the provider, and the project test
terraform/variables.tf         every value, from TF_VAR_ in cluster.sh
terraform/cluster-profile.tf   the registry, the four packs, the profile
terraform/cluster.tf           the appliances, and the cluster
terraform/outputs.tf           the ids, the console link, the kubeconfig
terraform/values/              the vendored pack values
```

`terraform/.terraform.lock.hcl` is committed: it pins the provider for every
workstation. Nothing else generated reaches the checkout, because
`scripts/cluster.sh` sets `TF_DATA_DIR` to the state directory of the project.
