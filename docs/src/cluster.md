# Make the cluster

Palette makes the cluster from the hosts that registered. The workstation runs
the virtual machines. Palette holds the cluster profile and the cluster.

Complete [Create the hosts](./hosts.md) first. `just palette-hosts` must list
every host before you start.

## This step has no recipe yet

Every other action in this repository is a recipe. This one is not, so it is the
one gap against [project rule 1](./rules.md#1-every-action-is-a-recipe).

The plan is Terraform with the Spectro Cloud provider, for the cluster profile
and the cluster only. The projects, the tokens, and the virtual machines keep
their recipes. The steps below are the console steps until then.

No cluster of this lab is complete yet, so read the steps below as a summary of
the Palette documentation, not as a tested procedure.

## 1. Make the cluster profile

The profile is the combination under test. The lab exists to give it hosts.

Select **Palette eXtended Kubernetes - Edge (PXK-E)** for the Kubernetes layer.
Add the CNI, the CSI, and the add-on packs to test.

## 2. Make the cluster

1. Make a cluster and select the profile.
2. Assign the registered hosts. Give the control plane pool the `-cp-` hosts
   and the worker pool the `-wk-` hosts.
3. Wait for the deployment. Palette shows the progress of each pack.

The libvirt domain name and the Palette host name are the same, so `just ls` and
the Palette host list agree.

## The virtual address

A lab with one control plane node needs no virtual address. `PALETTE_VIP_SKIP`
is `true` for that reason.

For more than one control plane node:

1. Set `PALETTE_VIP_SKIP` to `false` in the project file.
2. Run `just seed-clean`, then build the lab again.
3. Give the VIP in Palette. Use a free address of the lab subnet. See
   [The lab network](./network.md#address-plan).

## Run a second combination

The operating system image does not change between tests. Change the cluster
profile in Palette and deploy again. The hosts stay as they are.

To change the hosts themselves, see
[Create the hosts](./hosts.md#change-the-host-size-or-the-host-count).

## Remove the cluster

Delete the cluster in Palette first, then the profile. `just remove-project`
refuses while a project holds a cluster or a host. See
[Remove the lab](./teardown.md).
