# Prepare the workstation

The bash completion is optional. It gives the recipe names and their
arguments:

```bash
just bash-completion-install   # every shell, from the next login
source <(just bash-completion) # this shell, now
```

## 1. Install the packages

```bash
just host-setup
```

The recipe asks for your sudo password. It installs the virtualization tools,
and it adds you to the `libvirt` group and the `kvm` group.

Then restart the workstation. Your shell gets the new group at the next login,
and each `virsh` command fails without it. See
[Why a restart](./workstation.md#why-a-restart).

**Make SSH access available from a second computer first.** These packages
rebuild the initramfs, and the screen can stay blank after the restart. See
[The screen is blank](./troubleshooting.md#the-screen-is-blank-after-the-restart).

## 2. Install OpenTofu

```bash
just tofu-install
```

The cluster layer needs OpenTofu, and Ubuntu does not package it. The recipe
puts the pinned release in `~/.local/bin`, and it needs no root. See
[The tools that this repository needs](./workstation.md#the-tools-that-this-repository-needs).

## 3. Test the result

```bash
just preflight
```

The recipe prints `ok` or `FAIL` for each item, and it names the fix for each
failure. It makes no change. See
[What preflight tests](./workstation.md#what-preflight-tests).

When each item is `ok`, continue to [Configure the tenant](./tenant.md).
