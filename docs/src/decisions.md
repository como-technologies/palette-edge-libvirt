# Design decisions

This page records the decisions that shape the lab, and the evidence for each
one. Read it before you change a decision.

## Agent mode, not Edge Native

Palette gives two ways to make an edge host. The lab uses agent mode.

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

Agent mode also fits the purpose of the lab. The lab tests combinations of
Kubernetes, CNI, CSI, and add-ons. Those live in the cluster profile in
Palette, not in the operating system image, so a new combination needs no new
image and no new build.

The cost of the decision is the Kubernetes list. Agent mode gives PXK-E and
k3s. Edge Native gives more. PXK-E is the distribution that this lab tests, so
the cost is zero today.

## The token belongs to the project, the API key does not

A registration token registers hosts into one project. `just new-project`
therefore makes a token for each project and writes it into the environment
file of that project. `just remove-project` deletes the token with the project.

A Palette API key carries every permission of the user that owns it. Palette
gives a key no scope: the key object holds an expiry and a user, and nothing
else. Only three tenant roles can manage registration tokens, and the Project
Admin role is not one of them. A key is therefore a tenant credential, and it
lives outside the checkout at `~/.config/palette-edge-libvirt/api-key`.

An earlier version wrote the key into each project file. One project removal
then destroyed a tenant credential, and Palette does not show a key value again
after it makes one.

## The lab uses one subnet for each project

`just new-project` gives each project a different `LAB_NAME` and a different
`LAB_SUBNET`. Two labs then run at the same time, and no object of one lab
touches the other. The recipe reads the subnets of the other environment files
and of the libvirt networks, so a new project never takes a subnet that a
running lab uses.

## The cluster profile has no recipe yet

The lab makes the hosts. A person makes the cluster profile and the cluster in
Palette. This is the one gap against
[project rule 1](./rules.md#1-every-action-is-a-recipe).

The Palette CLI cannot close it. `palette project` gives `list`, `switch`, and
`deactivate` only, and the CLI has no command for a registration token. The
Terraform provider does have `spectrocloud_cluster_profile` and
`spectrocloud_cluster_edge_native`, so Terraform is the candidate for that
layer.
