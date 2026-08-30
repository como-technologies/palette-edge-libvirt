# The workstation

The cluster runs on one Linux workstation with KVM. This page describes what
`just host-setup` installs, why the restart is necessary, what `just preflight`
tests, and how much capacity a cluster needs.

For the three steps, see [Prepare the workstation](./host-setup.md).

## The packages

This is the recipe:

```just
{{#include ../../justfile:hostsetup}}
```

`just host-setup-undo` removes those packages. It also removes you from the two
groups.

The cluster needs no UEFI firmware package. The hosts boot a stock cloud image with
the standard firmware.

## Why a restart

`just host-setup` adds you to the `libvirt` group. A process gets its group list
at its start, so an existing shell keeps the old list. Without the `libvirt`
group, the libvirt socket refuses the connection:

```text
error: Failed to connect socket to '/var/run/libvirt/libvirt-sock': Permission denied
```

A logout is often sufficient. A restart is always sufficient.

The difference is the systemd user manager. `systemd-logind` keeps that manager
while one process of the user runs, and the default setting
`KillUserProcesses=no` permits this. The manager then holds the group list from
its own start time, and each new shell is a child of the manager. A new login
therefore repeats the old list.

`just preflight` compares the start time of the manager with the time of the
group change, so it names the correct fix:

- The manager is newer: log out and log in again.
- The manager is older: restart the workstation.

See
[The libvirt group is still absent](./troubleshooting.md#the-libvirt-group-is-still-absent-after-a-new-login).

## What preflight tests

`just preflight` makes no change. It prints `ok` or `FAIL` for each item, and it
stops with a failure code if one item fails. The recipe tests four groups:

| Group | What it tests |
| --- | --- |
| host | The `/dev/kvm` device, your access to it, the commands, and an ISO tool. |
| libvirt | Your `libvirt` group, the socket, and the connection. |
| palette | The token and the project name. |
| capacity | The CPU and memory that your topology needs against the workstation. |

Each `FAIL` line names its own fix, so run the recipe to see the current list.

`just infra-up` runs `just preflight` first, so a workstation that is not
ready stops the cluster before it makes any object.

## Capacity

The default topology is one control plane node and two worker nodes. That needs
16 vCPU and 40 GB of memory.

The reference workstation is a System76 Thelio with 32 cores and 128 GB. A host
can share CPU safely, but it cannot share memory, so memory sets the limit.
`just preflight` prints the request and the capacity, and it gives a warning
when the topology needs all of the memory.

The disks ask for 300 GB in total, but a qcow2 file is sparse. The true use is
much lower, because each host writes only a few gigabytes.

To make the cluster smaller, lower `WORKER_COUNT` or `WORKER_MEMORY_MB`. See
[Settings](./settings.md#the-cluster-size).

## The tools that this repository needs

| Tool | Function | Comes from |
| --- | --- | --- |
| `just` | Runs every recipe. | `cargo install just` |
| `libvirt`, `qemu-kvm`, `virtinst` | Runs the virtual machines. | `just host-setup` |
| `genisoimage` or `xorriso` | Builds the seed ISO. | `just host-setup` |
| `curl`, `python3` | Reads the Palette API and renders the seeds. | `just host-setup`, and Ubuntu gives python3 |
| `shellcheck` | Tests the shell scripts. | `just host-setup` |
| `mdbook`, `mdbook-mermaid`, `mdbook-gruvbox` | Builds this book. | `cargo install mdbook mdbook-mermaid mdbook-gruvbox` |
