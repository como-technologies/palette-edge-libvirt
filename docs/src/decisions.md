# Design decisions

This page records the decisions that shape the cluster, and the evidence for each
one. Read it before you change a decision.

## Agent mode, not Edge Native

Palette gives two ways to make an edge host. The cluster uses agent mode.

| | Edge Native | Agent mode |
| --- | --- | --- |
| Operating system | A custom image that you build | The stock Ubuntu cloud image |
| Build tool | CanvOS with Earthly | None |
| Docker on the workstation | Necessary | Not necessary |
| Build time for each change | 15 to 20 minutes | None |
| First boot | Installs the operating system | Starts the operating system |
| Kubernetes | PXK-E, k3s, RKE2, and more | PXK-E and k3s |

Three facts made the decision.

**Edge Native has no ready-made image.** Spectro Cloud publishes no generic
installer ISO. The CanvOS releases carry no asset, the downloads page holds no
installer ISO, and the tutorials build one on the workstation. That path
therefore always starts with a CanvOS build.

**CanvOS needs Docker.** Its `earthly.sh` runs `docker run --privileged`, it
mounts the Docker socket, and it stops with a message when Docker is absent.

**The agent mode documentation asks for no Docker on the host.** It says:
"Avoid installing Docker on the host where you want to install the agent."

Agent mode also fits the purpose of the cluster. The cluster tests combinations of
Kubernetes, CNI, CSI, and add-ons. Those live in the cluster profile in
Palette, not in the operating system image, so a new combination needs no new
image and no new build.

The cost of the decision is the Kubernetes list. Agent mode gives PXK-E and
k3s. Edge Native gives more. PXK-E is the distribution that this cluster tests, so
the cost is zero today.

## The token belongs to the project, the API key does not

A registration token registers hosts into one project. `just new-project`
therefore makes a token for each project and writes it into the environment
file of that project. `just remove-project` deletes the token with the project.

A Palette API key carries every permission of the user that owns it. Palette
gives a key no scope: the key object holds an expiry and a user, and nothing
else. Only three tenant roles can manage registration tokens, and the Project
Admin role is not one of them. A key is therefore a tenant credential, and it
lives outside the checkout at `~/.config/palette-edge-libvirt/api-key`. Every
other cluster file moved out of the checkout for the same reason. See
[The tooling directories](./directories.md).

An earlier version wrote the key into each project file. One project removal
then destroyed a tenant credential, and Palette does not show a key value again
after it makes one.

## The cluster uses one subnet for each project

`just new-project` gives each project a different `CLUSTER_NAME` and a different
`CLUSTER_SUBNET`. Two clusters then run at the same time, and no object of one cluster
touches the other. The recipe reads the subnets of the other environment files
and of the libvirt networks, so a new project never takes a subnet that a
running cluster uses.

## OpenTofu builds the cluster layer

The cluster profile and the cluster were the one gap against
[project rule 1](./rules.md#1-every-action-is-a-recipe). `just cluster-up` and
`just cluster-down` close it, with the Spectro Cloud provider and the resources
`spectrocloud_cluster_profile` and `spectrocloud_cluster_edge_native`.

The Palette CLI could not close it. `palette project` gives `list`, `switch`,
and `deactivate` only, and the CLI has no command for a registration token or a
cluster profile.

**OpenTofu and not Terraform.** OpenTofu is the fork with the MPL licence, the
provider is the same one, and the configuration language is the same. Neither
one is in the Ubuntu package list, so either needs an install recipe. `just
tofu-install` takes the release archive, tests its checksum, and puts the binary
in `~/.local/bin`, which needs no root.

**The layers below keep their recipes.** OpenTofu owns two objects only: the
profile and the cluster. The project, the token, and the machines have working
recipes with clear failure messages, and Terraform state adds nothing to them.
The API key never becomes a variable, so it reaches no state file.

## The pod range is not the pack default

The `edge-k8s` pack gives the pods `192.168.0.0/16`. That range holds every
cluster subnet that `just new-project` allocates, and it holds most home and
office networks as well.

Calico gives no NAT to a destination inside its own pool. A pod that asks the
gateway of the cluster network for DNS therefore sends a packet from a pod
address, the gateway drops it, and every name stays unresolved. The failure is
quiet and late: `kubectl get nodes` reports three ready nodes, and Palette waits
for a management agent that cannot reach `api.spectrocloud.com`. The cluster
sits in `Provisioning` until the recipe times out.

`POD_CIDR` replaces that one line of the pack values, and the default is
`10.244.0.0/16`. The service range `192.169.0.0/16` stays as the pack gives it,
because no libvirt network of this repository uses `192.169`.

The other way to correct the overlap is to move the cluster subnet out of
`192.168.0.0/16`. It was not taken: `192.168` is the address space that libvirt
and every example use for a NAT network, and one line of pack values is a
smaller change than a new address plan.

## The cluster always has a virtual address

Palette refuses a cluster that gives no control plane endpoint. It answers
`Parameter 'Host endpoint' should not be empty`, and it does that for one
control plane node as firmly as for three.

`CLUSTER_VIP` is therefore never empty, and `PALETTE_VIP_SKIP` is `false` so
kube-vip claims that address. `just new-project` writes the `.10` address of the
subnet it allocated, which is below the DHCP pool.

The earlier default was the opposite: skip kube-vip for a single control plane
node. That default was correct while nothing made a cluster, and it fails as
soon as something does. The two settings sit in two different layers, so
`just cluster-up` tests them together before it makes anything.
