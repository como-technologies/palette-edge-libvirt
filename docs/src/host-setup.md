# Prepare the workstation

Three steps make a new workstation ready. Do them one time.

> **Turn on the completion first.** It saves the most typing on this page and
> every page after it.
>
> ```bash
> just bash-completion-install   # every shell, from the next login
> source <(just bash-completion) # this shell, now
> ```
>
> The completion gives the recipe names, and it also gives the arguments: the
> host names, the roles `control` and `worker`, and the project names. See
> [Bash completion](./recipes.md#bash-completion).

## 1. Install the packages

```bash
just host-setup
```

The recipe asks for your sudo password. It installs the virtualization tools
and adds you to the `libvirt` group and the `kvm` group.

## 2. Restart the workstation

**Make SSH access available from a second computer first.** These packages
start a rebuild of the initramfs, and the screen can stay blank after the
restart. See
[The screen is blank](./troubleshooting.md#the-screen-is-blank-after-the-restart).

A restart gives your shell the new group. Without the group, every `virsh`
command fails. See [Why a restart](./workstation.md#why-a-restart).

## 3. Test the result

```bash
just preflight
```

The recipe prints `ok` or `FAIL` for each item, and it names the fix for each
failure. It makes no change.

When every item is `ok`, continue to
[Configure the tenant](./tenant.md).

## More

[The workstation](./workstation.md) describes the packages, the reason for the
restart, each test, and the capacity that a lab needs.
