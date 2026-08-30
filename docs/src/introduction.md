# Introduction

`palette-edge-libvirt` builds a Kubernetes test cluster on one workstation. It uses Spectro Cloud Palette (Profiles, Packs, and Edge) to create
and remove test Kubernetes clusters on libvirt/KVM virtual machines.

## Purpose

The tooling validates a combination of an operating system, a CNI, a CSI, and
add-on packs. You test the combination on virtual machines first. You commit the
combination to real hardware only after the test passes.

The reference workstation is a System76 Thelio with 32 cores and 128 GB of RAM.
Any Linux workstation with KVM and sufficient memory works.

## How the parts fit together

| Part | Function |
| --- | --- |
| Palette SaaS | Holds the cluster profiles and the packs. Registers the hosts. |
| Ubuntu cloud image | The stock operating system. The tooling builds no image. |
| Seed ISO | Gives the agent your tenant endpoint, project, and token. |
| Palette agent | Installs at the first boot and registers the host. |
| libvirt / KVM | Runs the virtual machines. |
| `just` | Runs every action in this repository. |
| mdBook | Builds this documentation. |

The tooling uses Palette **agent mode**. Each host runs a stock Ubuntu cloud
image, so it builds no operating system image. See
[Design decisions](./decisions.md#agent-mode-not-edge-native).

[Architecture](./architecture.md) gives the full diagram, the boot sequence of
one host, and the location of each part of the state.

## Start here

1. [Prepare the workstation](./host-setup.md) — `just host-setup`, then restart.
2. [Configure the tenant](./tenant.md) — `just api-key-set`.
3. [Create a project](./project.md) — `just new-project <project>`.
4. [Create the machines](./machines.md) — `just infra-up`.
5. [Create the cluster](./cluster.md) — in Palette, for now.

Read the [project rules](./rules.md) before you change the repository.
