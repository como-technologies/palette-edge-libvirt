# Prepare the workstation

This page installs the virtualization tools and tests the result.

> **Turn on the completion first.** It saves the most typing on this page and
> every page after it.
>
> ```bash
> just bash-completion-install   # every shell, from the next login
> source <(just bash-completion) # this shell, now
> ```
>
> The completion gives the recipe names, and it also gives the arguments: the
> host names, the roles `control` and `worker`, and the project names. It is
> safe for every project, because it reads the recipes from `just` itself. See
> [Bash completion](./recipes.md#bash-completion).

## 1. Install the packages

Run this recipe one time on a new workstation. The recipe asks for your sudo
password.

```bash
just host-setup
```

The recipe installs `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`,
`virtinst`, `genisoimage`, `curl`, and `shellcheck`. It also adds your
user to the `libvirt` group and the `kvm` group.

To remove these packages again, run `just host-setup-undo`.

## 2. Apply the new group membership

**Restart the workstation.**

`just host-setup` adds you to the `libvirt` group. Your shell gets the new group
only from a new session. Without the group, the libvirt socket refuses the
connection, and every `virsh` command fails.

A logout is often sufficient. A restart is always sufficient. The systemd user
manager can stay active across a logout and give the old group list to each new
shell. See
[The libvirt group is still absent](./troubleshooting.md#the-libvirt-group-is-still-absent-after-a-new-login).

`just preflight` tests for both conditions and names the correct fix.

**Before you restart, make SSH access available from a second computer.** The
qemu and libvirt packages start a rebuild of the initramfs. After the restart,
the screen can stay blank. You then need a second computer to correct the
condition. See
[The screen is blank after the restart](./troubleshooting.md#the-screen-is-blank-after-the-restart).

## 3. Test the result

```bash
just preflight
```

The recipe tests each item and prints `ok` or `FAIL`. It stops with a failure
code if an item fails. The recipe tests:

- The `/dev/kvm` device and your access to it.
- The `virsh`, `virt-install`, `qemu-img`, and `curl` commands.
- An ISO tool, either `genisoimage` or `xorriso`.
- The connection to libvirt.
- The `PALETTE_EDGE_TOKEN` value.
- The CPU and memory that your topology needs against the workstation capacity.

`just cluster-up` runs `just preflight` first, so a bad workstation stops the
lab before it makes any object.

## Capacity

The default topology needs 16 vCPU and 40 GB of RAM. It also needs about 300 GB
of disk, but the qcow2 files are sparse, so the true use is much lower. The reference workstation
has 32 cores and 128 GB. `just preflight` prints the request and the capacity.
Change the values in `.env` for a smaller workstation. See
[Configure the tenant](./configuration.md).
