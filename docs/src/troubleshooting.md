# Troubleshooting

## `just preflight` reports a FAIL

Read the detail column. It names the fix. The usual causes are:

| Item | Cause | Fix |
| --- | --- | --- |
| `/dev/kvm` | The BIOS disables virtualization. | Enable VT-x or AMD-V in the BIOS. |
| `libvirt group` | Your session is older than `just host-setup`. | Log out and log in again. |
| `daemon` | The libvirt socket is not active. | Run `sudo systemctl enable --now libvirtd.socket`. |
| `virsh`, `virt-install` | The packages are absent. | Run `just host-setup`. |
| `PALETTE_EDGE_TOKEN` | This checkout reads no project. | Run `just projects`, then `just default-project <project>`. |

## The screen is blank after the restart

`just host-setup` installs the qemu and libvirt packages. Those packages start a
rebuild of the initramfs. After the restart, the boot splash (Plymouth) can keep
control of the GPU. The login screen runs behind the splash, so the monitor
stays blank.

Connect to the workstation with SSH from a second computer. Then test the boot:

```bash
systemd-analyze                 # reports that the boot is not finished
systemctl list-jobs             # plymouth-quit-wait.service is "running"
```

Each remaining boot job waits for `plymouth-quit-wait.service`.
`graphical.target` never becomes active.

To correct the condition:

```bash
sudo plymouth quit              # release the GPU and let the boot finish
sudo systemctl restart gdm      # give the login screen a new start
```

The login screen shows on the monitor again. `sudo plymouth quit` needs a
terminal for the password, so use a normal SSH shell for it.

To prevent the condition, remove the boot splash. Edit `/etc/default/grub` and
delete the word `splash` from `GRUB_CMDLINE_LINUX_DEFAULT`. Then:

```bash
sudo update-grub
```

The workstation then shows the boot messages instead of a splash image. This
change is a workstation setting. It is not part of the cluster, so it has no recipe.

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

Test the project name first. This is the most common cause, and it takes one
second:

```bash
just palette-projects
```

A wrong `PALETTE_PROJECT` gives no error. The host starts correctly, the agent
runs, and the host never shows. The name is case sensitive.

If the project name is correct, test each item:

1. **The agent is still installing.** cloud-init installs the packages first,
   which takes some minutes. Run `just host-status <host>`.
2. **The host has no address.** Run `just ip <host>`. If the command reports no
   lease, the network is down. Run `just net-up`.
3. **cloud-init failed.** Open the console with `just console <host>`. Log in
   as `ubuntu` with the password from `HOST_PASSWORD`. Then run:

   ```bash
   sudo cloud-init status --long
   sudo journalctl -u cloud-final --no-pager | tail -40
   ```

4. **The host has no route to the internet.** The agent needs
   `api.spectrocloud.com` on port 443, and cloud-init needs the Ubuntu archive.
   Test the NAT network from the workstation.
5. **The token is wrong.** Open Palette at **Tenant Settings**, then
   **Registration Tokens**. Confirm that the token is active and not expired.
   Then follow [Rotate the token](./edge-hosts.md#rotate-the-token).
6. **The seed ISO is old.** A change to the project file does not change an
   existing seed.
   Run `just seed-clean`, then `just seed-all`, then rebuild the host.

## The host installs the agent but never registers

Read the log that the installation writes. Open the console, log in as `ubuntu`
with the password from `HOST_PASSWORD`, then:

```bash
cloud-init status --long
sudo tail -40 /var/log/palette-agent-install.log
```

`palette edge installation completed successfully` means the agent installed.
The agent services run at boot stages, so the host registers only after a
restart. cloud-init makes that restart, and the host appears one or two minutes
later.

To see whether the services ran:

```bash
systemctl list-units --all 'spectro*'
```

`inactive dead` for every service means that the restart did not happen.

## cloud-init reports "Illegal option -o pipefail"

cloud-init runs each `runcmd` entry with `/bin/sh`, and on Ubuntu that is dash.
A bash feature stops the whole script, and cloud-init reports the failure only
in `cloud-init status --long`. The host then looks correct and does nothing.

Keep `runcmd` entries simple. Put a script in `write_files` with a bash line at
the top, and call that script from `runcmd`.

## The agent installs again at each boot

cloud-init writes a marker file at `/var/lib/palette-agent-installed` after a
correct installation. A second boot reads the marker and makes no change. If the
agent installs again, the first installation did not finish. Read the console
output for the error.

## `just host-down` fails on the undefine

A snapshot or a checkpoint holds the domain:

```bash
virsh snapshot-list <host>
virsh checkpoint-list <host>
```

Delete those, then run `just host-down <host>` again.

## `just net-down` reports that a domain carries the network

Remove the virtual machines first:

```bash
just infra-down
```

`just pool-down` refuses for the same reason. libvirt itself refuses neither
one: it removes a network that a running domain uses, reports success, and
leaves that domain with a bridge that is gone. The machine then reaches nothing,
never registers, and gives no sign of the cause. The recipes test for this
before they remove either object.

Give `FORCE=1` to pass the test, when you know that the machines go next:

```bash
FORCE=1 just net-down
FORCE=1 just pool-down
```

## A machine runs, and `just cluster-up` says it holds no record

The Palette agent installs one time and writes a marker file. A machine that
lost its record therefore does not register again by itself, and `just infra-up`
skips a domain that exists. Build those machines again:

```bash
just infra-down && just infra-up
```

## `just image-fetch` fails

The release name in `UBUNTU_RELEASE` does not exist, or the workstation has no
route to `cloud-images.ubuntu.com`. Use a release code name, such as `noble` or
`jammy`, not a number.

A failed download leaves a `.part` file. `image-fetch` continues that download
on the next run. Delete the `.part` file to start again.

If the message says that the image does not match the checksum, the recipe
deletes the image and downloads it again. Canonical rebuilds the current image,
so an old cached image can be correct but different.

## `just remove-project` reports HTTP 500

Palette refuses to delete a project while a registration token names it as its
default project:

```text
Palette says: Unable to delete the resource as pe-thelio edgetoken(s) in-use
Palette code: DeletionResourceInUseError
```

`just remove-project` deletes the token first, so this message means that the
token is a different one. Perhaps you made it by hand, and it names this
project. Palette lists the tokens at **Tenant Settings** >
**Registration Tokens**. Change the default project of that token, or delete
it. Then run the recipe again.

## A host registers into no project

The registration token has no default project. `just palette-hosts` shows
nothing, and the host does not appear in the console.

Palette returns the binding as `spec.defaultProject` but accepts it as
`spec.defaultProjectUid`. A token that was made with the wrong field is
accepted and stays unbound. To see the binding of every token:

```bash
just palette-tokens
```

A token with no project needs a replacement. Run `just remove-project NAME`
and `just new-project NAME` again, or set the default project of the token in
the console at **Tenant Settings** > **Registration Tokens**.

## `just cluster-up` reports "Host endpoint should not be empty"

```text
Parameter 'Host endpoint' should not be empty
```

Palette refuses a cluster that gives no control plane endpoint. Set
`CLUSTER_VIP` in the project file to a free address of the cluster subnet, below
the DHCP pool. See [The virtual address](./cluster-profile.md#the-virtual-address).

The recipe tests the value first, so this message reaches you only when
`CLUSTER_VIP` names an address that Palette itself rejects.

## `just cluster-up` reports that a host is not ready

```text
error: these host(s) are not ready in project <name>:
       theliolab-wk-2
```

The cluster layer builds on the layer below it. Run `just infra-up`: it is
idempotent, and it waits until every host registers. `just host-status <host>`
shows the progress of one host, and
[A host does not show in Palette](#a-host-does-not-show-in-palette) covers the
rest.

## The cluster builds for an hour and then fails

Read the pack that stopped, in the Palette console. Three causes are specific to
this repository:

- **Nothing answers at `CLUSTER_VIP`.** The seed ISO of each host must carry
  `PALETTE_VIP_SKIP=false`, or the agent installs no kube-vip. `just config`
  shows the value that the recipes use now. To correct it, set the value in the
  project file and build the machines again: `just seed-clean`, `just
  infra-down`, `just infra-up`.
- **The pod range holds the cluster subnet.** See the next item.
- **A pack version does not fit the others.** `just palette-packs <name>` lists
  the versions that the public registry offers. Palette lists Ubuntu with PXK-E
  and Calico as a verified combination.

`just cluster-down` removes the cluster and the profile, so a second attempt
starts clean.

## The nodes are ready but Palette keeps the cluster in Provisioning

The nodes are up and the cluster does nothing. Read the log of the management
agent from the control plane node:

```bash
kubectl -n cluster-<cluster-uid> logs deploy/cluster-management-agent-lite
```

This message means the pods cannot resolve a name:

```text
dial tcp: lookup api.spectrocloud.com on 192.169.0.10:53: server misbehaving
```

Read the CoreDNS log next. A timeout to the gateway of the cluster network is
the overlap between the pod range and that network:

```text
[ERROR] plugin/errors: 2 api.spectrocloud.com. A: read udp 192.168.98.193:60862->192.168.140.1:53: i/o timeout
```

`POD_CIDR` must hold neither `CLUSTER_SUBNET` nor the address of your
workstation. `just config` shows both. The pack default `192.168.0.0/16` holds
both, so the project file replaces it. See
[The pod range](./cluster-profile.md#the-pod-range).

The pod range belongs to the Kubernetes layer, and Kubernetes does not change it
in place. Build the cluster layer again:

```bash
just cluster-down
just cluster-up
```

## `just cluster-up` reports that OpenTofu is absent

```text
error: OpenTofu is not installed. Run: just tofu-install
```

The recipe installs the pinned release into `~/.local/bin`. If the command still
does not run after that, `~/.local/bin` is not on your `PATH`. The recipe prints
a warning when it finds that, and the correction is one line in your shell
profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

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
`WORKER_COUNT` or `WORKER_MEMORY_MB` in the project file. Then run
`just infra-down` and
`just infra-up`.

## `just host-up` cannot write to the pool directory

`just pool-up` gives the pool directory to your user, so `host-up` copies the
cloud image without sudo. If the directory still belongs to root, run:

```bash
just pool-up
```

The recipe tests the ownership and corrects it. It is idempotent, so it makes no
other change.
