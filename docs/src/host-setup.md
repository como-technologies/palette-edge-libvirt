# Prepare the workstation

This page installs the virtualization tools and tests the result.

## 1. Install the packages

Run this recipe one time on a new workstation. The recipe asks for your sudo
password.

```bash
just host-setup
```

The recipe installs `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`,
`virtinst`, `ovmf`, `genisoimage`, `curl`, and `shellcheck`. It also adds your
user to the `libvirt` group and the `kvm` group.

To remove these packages again, run `just host-setup-undo`.

## 2. Apply the new group membership

Log out and log in again. Your shell gets the new groups only after a new login.

## 3. Test the result

```bash
just preflight
```

The recipe tests each item and prints `ok` or `FAIL`. It stops with a failure
code if an item fails. The recipe tests:

- The `/dev/kvm` device and your access to it.
- The `virsh`, `virt-install`, `qemu-img`, and `curl` commands.
- An ISO tool, either `genisoimage` or `xorriso`.
- The OVMF firmware for UEFI boot.
- The connection to libvirt.
- The `PALETTE_EDGE_TOKEN` value.
- The CPU and memory that your topology needs against the workstation capacity.

`just cluster-up` runs `just preflight` first, so a bad workstation stops the
lab before it makes any object.

## Capacity

The default topology needs 16 vCPU and 40 GB of RAM. The reference workstation
has 32 cores and 128 GB. `just preflight` prints the request and the capacity.
Change the values in `.env` for a smaller workstation. See
[Configure the tenant](./configuration.md).
