# Introduction

`palette-edge-libvirt` builds and removes Kubernetes test clusters on one
workstation, from Spectro Cloud Palette packs and libvirt virtual machines.

## Let's just do it!

| Type this | More |
| --- | --- |
| `just host-setup` | [Prepare the workstation](./host-setup.md). Installs libvirt and KVM. Restart when it finishes. |
| `just tofu-install` | [Install OpenTofu](./host-setup.md#2-install-opentofu) into `~/.local/bin`. Needs no root. |
| `just api-key-set` | [Configure the tenant](./tenant.md). Reads your Palette API key without an echo. |
| `just new-project <project>` | [Create a project](./project.md). Makes the Palette project, its registration token, and its settings. |
| `just infra-up` | [Create the machines](./machines.md). Returns when every host registers, in about 3 minutes. |
| `just cluster-up` | [Create the cluster](./cluster.md). The profile and the cluster, in about 11 minutes. |
| `just cluster-kubeconfig` | [Use the cluster](./cluster.md#5-use-the-cluster). Prints the administrator kubeconfig. |

## Let's do it in reverse

Every recipe that makes something has a twin that removes it, so the table above
also reads from the bottom up:

| Type this | More |
| --- | --- |
| `just cluster-down` | [Remove the cluster](./cluster.md#remove-the-cluster). The cluster and the profile. The machines stay. |
| `just infra-down` | The host records, the machines, the pool, and the network. Refuses while a cluster holds them. |
| `just remove-project <project>` | The Palette project, its registration token, its settings, and its OpenTofu state. |
| `just image-clean` | The Ubuntu cloud image in the cache. |
| `just api-key-clear` | The Palette API key. |
| `just tofu-uninstall` | The OpenTofu that `just tofu-install` wrote. |
| `just host-setup-undo` | libvirt, KVM, and the group membership. |

*...and it's like we were never here* 😏

## More

[Getting started](./host-setup.md)
