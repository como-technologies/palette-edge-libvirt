# Prepare the workstation

## 0. Completions (optional)

```bash
just bash-completion-install   # every shell, from the next login
source <(just bash-completion) # this shell, now
```

## 1. Install the packages

```bash
just host-setup   # libvirt, KVM, the tools, and the libvirt and kvm groups
```

Restart the workstation for the new groups. See
[Why a restart](./workstation.md#why-a-restart).

**Make SSH access available from a second computer first.** These packages
rebuild the initramfs, and the screen can stay blank after the restart. See
[The screen is blank](./troubleshooting.md#the-screen-is-blank-after-the-restart).

## 2. Install OpenTofu

```bash
just tofu-install   # the pinned release into ~/.local/bin, no root
```

Ubuntu does not package OpenTofu. See
[The tools that this repository needs](./workstation.md#the-tools-that-this-repository-needs).

## 3. Test the result

```bash
just preflight   # ok or FAIL for each item, with the fix for each failure
```

When each item is `ok`, continue to [Configure the tenant](./tenant.md).
