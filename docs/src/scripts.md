# Writing a script

The `justfile` is the interface and the configuration. `scripts/*.sh` holds all
of the logic. Each script reads its input from the environment. Thus
`shellcheck` can examine it, and you can run it alone:

```bash
PALETTE_EDGE_TOKEN=x scripts/seed-iso.sh test-1 ./seeds ./build
NETWORK=pe-net SUBNET=192.168.140 BUILD_DIR=./build scripts/net-up.sh
```

`scripts/lib.sh` holds the functions that all scripts use.
`scripts/palette-lib.sh` holds the Palette API. Include these two files. Do not
execute them.

This page lists the conditions that caused a failure in this repository. Each
one gives no error message: the script returns 0 and does the incorrect
operation.

## `set -o pipefail` can stop a script with no message

Each script sets `-euo pipefail`. Thus this line stops the script with no
message when the pool is absent:

```bash
x="$(virsh pool-dumpxml "$POOL" | sed -n '...')"
[ -n "$x" ] || die "..."
```

The `die` command below it does not operate. A person wrote that `die` command
for this condition.

`host-down.sh` had this failure. It removed the domain and its definition. Then
it stopped, and it did not delete the disk. A disk file of 100 GB stayed on the
workstation, and no domain referred to it.

The same failure made `just projects` print no data when a project file had no
`CLUSTER_NAME` value. `grep` gives a failure code when it finds no match.

**Add `|| true` to each command substitution that can fail in the first stage.**
The test below it reports the condition:

```bash
x="$(virsh pool-dumpxml "$POOL" | sed -n '...' || true)"
[ -n "$x" ] || die "the pool $POOL is absent. Run: just pool-up"
```

## `die` in a pipeline stops only the subshell

`die` calls `exit`. A function in a pipeline operates in a subshell. Thus `die`
stops the subshell only. The reader function then receives no input, and the
person sees a Python traceback and not the message.

Call `need_api_key` and `need_project` at the start of the script. Do not call
them in a pipeline only. Each script that reads Palette does this.

## `UID` is a read-only variable in bash

```text
bash: UID: readonly variable
```

Thus `UID=x python3 -c '...'` fails. The functions use `PEL_UID`. `shellcheck`
does not find this error.

## A `virsh` table has a header row

`virsh domiflist` and `virsh net-dhcp-leases` print a header row. An `awk`
program with field numbers can match that row. `host-ip.sh` showed the address
of a host as `Protocol`. The correction is to match the format of a MAC address.

## An interactive `gh` function stops a script with `set -u`

A `gh` shell function goes into each child shell. A function that reads
`$GH_REPO` with no default value stops with `set -u`. It gives no message when
the standard error goes to a different file.

Scripts use `command gh`. Do not use `gh` alone.

## A background `kubectl port-forward` continues after its shell stops

`dashboard.sh` cannot use `exec`. The kubeconfig is in a temporary directory,
and the shell must continue to operate to remove that directory.

A child process can continue after the shell receives a signal. The child
process then holds the local port. It connects to a cluster that is no longer
present.

Keep the process id. Stop that process in the `EXIT` trap. Test the port with
`/dev/tcp` **before** the recipe prints a URL. Then the failure message names
the condition.

## Do not change the mode of all files in the state directory

`TF_DATA_DIR` is below the state directory, and it holds the provider program. A
`chmod 600` operation on all files causes this error in the next run:

```text
fork/exec .../terraform-provider-spectrocloud: permission denied
```

`protect_state` in `cluster.sh` uses `-maxdepth 1`.

## `systemctl list-units` shows only the units that systemd loaded

A service that is stopped and not loaded does not show. A test that uses this
command reports "not installed" while the unit file is on the disk. `svc.sh
install` then refuses with the message "exists".

Examine the **file**. `runner_units` in `lib.sh` does this.

## libvirt does not refuse to remove an object that is in use

`virsh net-destroy` returns **0** for a network that a running domain uses. The
domain continues to operate with a bridge that is not present. The domain gets
no address, it does not register, and there is no message.

An initial version of `net-down.sh` examined the exit code for this condition.
Thus that guard never operated. `domains_using_network` and `domains_using_pool`
in `lib.sh` make the test that libvirt does not make. `FORCE=1` bypasses the
test.

## Do the root operations before you make the object

An initial version of `pool-up.sh` defined the pool, and then it did `sudo
chown` on the directory. On a workstation with no stored password, this made a
pool that was defined, inactive, and not usable. The next run reported "already
defined", and then it failed at the same point.

The script now does all `sudo` operations first. If there is no terminal and no
stored password, the script names the two commands to run manually.

## `rmdir` needs write permission on the parent directory

`/var/lib/libvirt/images` is `drwx--x--x root:root`. Thus `pool-down` cannot
remove its own pool directory. `pool-up` gave that directory to your user, but
that permission is not sufficient. The directory permits traversal and not a
read operation. Thus `[ -d ]` operates and `ls` does not.

Report the two conditions separately:

- "The directory still holds a file" is a condition to correct.
- "The parent directory belongs to root" is not a fault. A message that reports
  it as a fault makes a person look for an error that is not there.

## A recipe must not wait for a condition that cannot occur

`hosts-wait` sent a request to the API every 15 seconds for the full
`REGISTER_TIMEOUT` period, 900 seconds, when there were no virtual machines.

The recipe now examines libvirt first. A name with no domain and no record fails
in one second. The recipe also counts the `in-use` state as registered, as
`cluster.sh:require_ready_hosts` does. Without that, a second run on a cluster
that operates waits for the full period.

## Do not give libvirt a file in the checkout

libvirt gives each file that a domain uses to the `libvirt-qemu` user. It does
not return the file when the domain fails to start. Thus a seed ISO in the
checkout stops belonging to you. The seed directory is also mode 0700, and the
qemu user cannot enter it.

`host-up.sh` copies the seed into the storage pool, and it attaches that copy.
`host-down.sh` and `host-eject.sh` delete the files in the pool. `seed-iso.sh`
deletes its output file before it writes. Thus you can build a seed again with
no `sudo`.

## Examine the credential, and not the file

`infra-down` examined `[ -s "$(api_key_file)" ]`. A key in the environment is a
correct method to give a key for one command. It is also the only method that
continuous integration uses.

Thus each CI run did no Palette operation in this layer, and it gave no message.
It left one host record for each machine that it deleted.

`have_api_key` examines the two sources. Use it where an absent key is a
condition to report. Use `need_api_key` where an absent key must stop the
script.

## A guard needs a test

Each item on this page is a guard in a script. A small change to one `if`
statement can stop a guard. The recipe then returns 0, and there is no message.

`just test` examines the guards. It uses no libvirt and no tenant, and it takes
approximately one second. `just lint` runs it. Add a test when you add a guard.
See [Tests](./tests.md).

## The justfile

### A recipe that fails prints only its own message

`set no-exit-message` removes the line that `just` prints after a failure:

```text
error: recipe `palette-hosts` failed on line 300 with exit code 1
```

That line names a line of the `justfile`. It helps a person who changes the
justfile. It gives no information to a person who uses the tooling. It is also
the last line, thus it stays on the screen while the correction moves up.

**Thus each `die` message must name the correction.** It is the only text that
the person reads.

The exit code does not change. `just` continues to print its own argument
errors, for example an incorrect number of positional arguments.

Boolean settings use the short format. Use `set no-exit-message`. Do not use
`set no-exit-message := true`, or `just --fmt --check` fails.

### `just` has no `state_directory()` function

`just` has `config_directory()`, `data_directory()`, and `cache_directory()`.
The justfile makes the XDG state path directly:

```just
{{#include ../../justfile:dirs}}
```

### A recipe must hold no default value

`just config` had a copy of each default value from the `justfile`. One value
became different. The recipe then reported a control plane disk of 60 GB, and
the recipes made one of 100 GB.

The recipe now sends each computed value to `config.sh`, and that script prints
the values that it receives.

A workflow must also hold no copy. The e2e workflow had its own `CLUSTER_NAME`
value, subnet, virtual address, and pod range. These became different after the
first change. `just ci-env` prints them, and the workflow puts them in
`GITHUB_ENV`.

### A parameter names a kind of value

Examples: `host-up host role="worker"`, `default-project project`,
`test filter=""`.

The completion reads the recipe names from `just --summary`. It reads the
parameters from `just --dump --dump-format json`. Then it completes by the
parameter **name**. Thus it holds no list of recipes, and a new recipe gets
completion with no change.

Use a parameter name of `host`, `project`, `role`, `action`, or `filter`. For a
new kind, add the name to `_PEL_KINDS` in `scripts/bash-completion.sh`. For free
text, add the name to `_PEL_KINDS_FREE`. `scripts/lint-params.sh` stops the
build for a name that the completion does not know.

## The documentation

### mdBook does not fail on an absent anchor

mdBook fails on an absent **file**. If the file is present and the anchor is
absent, mdBook writes an empty code block and gives no message. Thus a changed
anchor name removes an example from the book.
[Rule 5](./rules.md#5-the-documentation-includes-the-source) prevents this
condition. This failure occurred during the change of the layer names.

`scripts/lint-includes.sh` examines the two parts of each include.

### Change the template when you add a setting

`just new-project` writes values into `templates/project.env`. That file also
holds the anchors that this book includes. Thus a new setting that is not in
that file is a setting that the book does not describe.
