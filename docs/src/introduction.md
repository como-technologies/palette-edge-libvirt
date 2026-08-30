# Introduction

`palette-edge-libvirt` builds and removes Kubernetes test clusters on one
workstation, from Spectro Cloud Palette packs and libvirt virtual machines.

## Let's just do it!

| Type this | More |
| --- | --- |
| `just host-setup` | [Prepare the workstation](./host-setup.md). Installs libvirt and KVM. Restart when it finishes. |
| `just tofu-install` | [Install OpenTofu](./host-setup.md#3-install-opentofu) into `~/.local/bin`. Needs no root. |
| `just api-key-set` | [Configure the tenant](./tenant.md). Reads your Palette API key without an echo. |
| `just new-project <project>` | [Create a project](./project.md). Makes the Palette project, its registration token, and its settings. |
| `just infra-up` | [Create the machines](./machines.md). Returns when every host registers, in about 3 minutes. |
| `just cluster-up` | [Create the cluster](./cluster.md). The profile and the cluster, in about 45 minutes. |
| `just cluster-kubeconfig` | [Use the cluster](./cluster.md#5-use-the-cluster). Prints the administrator kubeconfig. |

The first three rows are one time for each workstation. Almost all of the hour
that the last three take is a wait.

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

`just nuke` is the first three rows in one command. The last four stay, because
none of them belongs to one project.

[Remove everything](./teardown.md) describes what each recipe leaves, and
[project rule 2](./rules.md#2-every-create-recipe-has-a-remove-recipe) is why
each one has a twin.

## More

[Architecture](./architecture.md) names each part, and walks one machine from a
cloud image to a node of the cluster.
[Recipes](./recipes.md) describes the two layers and every recipe.
[Troubleshooting](./troubleshooting.md) names the fix for each failure that this
tooling has met.

Read the [project rules](./rules.md) before you change the repository.
