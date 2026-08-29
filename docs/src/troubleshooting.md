# Troubleshooting

## `just preflight` reports a FAIL

Read the detail column. It names the fix. The usual causes are:

| Item | Cause | Fix |
| --- | --- | --- |
| `/dev/kvm` | The BIOS disables virtualization. | Enable VT-x or AMD-V in the BIOS. |
| `libvirt group` | Your session is older than `just host-setup`. | Log out and log in again. |
| `daemon` | The libvirt socket is not active. | Run `sudo systemctl enable --now libvirtd.socket`. |
| `virsh`, `virt-install` | The packages are absent. | Run `just host-setup`. |
| `PALETTE_EDGE_TOKEN` | There is no `.env` file. | Run `cp .env.example .env` and edit it. |

## The libvirt connection fails after host-setup

`just host-setup` adds you to the `libvirt` group. A new group applies only to a
new login session. Your current shell keeps the old group list, so the libvirt
socket refuses the connection:

```text
error: Failed to connect socket to '/var/run/libvirt/libvirt-sock': Permission denied
```

**Log out and log in again.** Then run `just preflight` again.

`just preflight` reports this cause directly. It compares the group database
with the groups of the current process.

## The libvirt group is still absent after a new login

`just preflight` shows this message:

```text
FAIL  libvirt group   the systemd user manager is older than the group. Restart the workstation.
```

The systemd user manager (`user@UID.service`) holds the group list from its own
start time. `systemd-logind` keeps the manager while one process of the user
runs. The default setting `KillUserProcesses=no` permits this. A background
process therefore keeps the manager alive across a logout.

Each new shell is a child of that manager, so a new login gives the same old
group list. The group database is correct, but no new process can see it.

**Restart the workstation.** This is the reliable correction.

To correct it without a restart, stop every process of the user. This also
stops the manager:

```bash
sudo loginctl terminate-user "$USER"
```

Then log in again. This command closes your terminals, your editor, and your
graphical session, so save your work first.

To see the two times that `just preflight` compares:

```bash
systemctl show "user@$(id -u).service" -P ActiveEnterTimestamp
stat -c '%y' /etc/group
```

If the manager time is earlier than the `/etc/group` time, a new login does not
help.

To test one command before you log out again, use `sg`:

```bash
sg libvirt -c 'just preflight'
```

`sg` applies the group to one command only. Use it for a test. Do not use it for
normal work.

The `/dev/kvm access` test can pass while the `libvirt group` test fails. These
are two different permissions. On many systems udev gives access to `/dev/kvm`
without the `kvm` group.

## A host does not show in Palette

Open the console first:

```bash
just console pe-cp-1
```

Then test each item:

1. **The host has no address.** Run `just ip pe-cp-1`. If the command reports no
   lease, the host is still in the installation, or the network is down. Run
   `just net-up`.
2. **The host has no route to the internet.** The agent needs
   `api.spectrocloud.com` on port 443. Test the NAT network from the workstation.
3. **The token is wrong.** Open Palette at **Tenant Settings**, then
   **Registration Tokens**. Confirm that the token is active and not expired.
   Then follow [Rotate the token](./edge-hosts.md#rotate-the-token).
4. **The project name is wrong.** `PALETTE_PROJECT` must match the project name
   in Palette exactly. The name is case sensitive.
5. **The seed ISO is old.** A change to `.env` does not change an existing seed.
   Run `just seed-clean`, then `just seed-all`, then rebuild the host.

## The host installs again at each boot

The system disk has no boot loader, so the firmware goes back to the installer
ISO. This means that the installation failed. Read the console output for the
error. Confirm that `install.device` in `templates/user-data.tmpl.yaml` names
the correct disk. The disk is `/dev/vda`, because `host-up.sh` uses `bus=virtio`.

## `just host-down` fails on the undefine

The domains boot UEFI, so libvirt keeps an NVRAM variable store for each domain.
`host-down.sh` passes `--nvram` to delete that store. If the command still fails,
a snapshot or a checkpoint holds the domain:

```bash
virsh snapshot-list pe-cp-1
virsh checkpoint-list pe-cp-1
```

Delete those, then run `just host-down pe-cp-1` again.

## `just net-down` reports that a VM uses the network

Remove the virtual machines first:

```bash
just cluster-down
just net-down
```

## `just iso-fetch` fails

The release asset for `EDGE_INSTALLER_VERSION` does not exist, or the
workstation has no route to GitHub. Test the version, or use the direct link
from your tenant. Open Palette, go to **Clusters**, then **Edge Hosts**, then
**Add Edge Host**. Put the link in `EDGE_INSTALLER_URL` in `.env`.

A failed download leaves a `.part` file. `iso-fetch` continues that download on
the next run. Delete the `.part` file to start again.

## The docs build fails on an include

The path is wrong, or the anchor is absent. The paths in `docs/src/*.md` are
relative to the markdown file, so the repository root is `../../`. Confirm that
the source file holds both `ANCHOR: name` and `ANCHOR_END: name`.

## `just lint` skips shellcheck

`shellcheck` is not installed. Install it:

```bash
sudo apt-get install shellcheck
```

The GitHub Actions workflow always installs it, so the check runs there.

## The workstation runs out of memory

`just preflight` prints the requested memory and the physical memory. Lower
`WORKER_COUNT` or `WORKER_MEMORY_MB` in `.env`. Then run `just cluster-down` and
`just cluster-up`.
