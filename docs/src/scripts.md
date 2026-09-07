# Writing a script

The `justfile` is the interface and the configuration. `scripts/*.sh` holds all
of the logic. Each script takes its input from the environment, so `shellcheck`
can read it and you can run it alone:

```bash
PALETTE_EDGE_TOKEN=x scripts/seed-iso.sh test-1 ./seeds ./build
NETWORK=pe-net SUBNET=192.168.140 BUILD_DIR=./build scripts/net-up.sh
```

`scripts/lib.sh` holds what every script shares, and `scripts/palette-lib.sh`
holds the Palette API. Both are sourced and never executed.

This page holds the traps. Each one cost a day, and each one is silent: the
script returns 0 and does the wrong thing.

## `set -o pipefail` turns a first failure into a silent exit

Every script sets `-euo pipefail`. So this line ends the script **with no
message at all** when the pool is absent:

```bash
x="$(virsh pool-dumpxml "$POOL" | sed -n '...')"
[ -n "$x" ] || die "..."
```

The `die` below it was written for exactly that case, and it never runs.

`host-down.sh` hit this. It destroyed the domain and removed its definition,
then stopped before it deleted the disk, so a 100 GB file stayed on the
workstation with nothing left to name it. The same bug made `just projects`
print nothing when a project file held no `CLUSTER_NAME`, because `grep` calls
"no match" a failure.

**Any command substitution whose first stage can fail needs `|| true`.** The
test below it is what reports the condition:

```bash
x="$(virsh pool-dumpxml "$POOL" | sed -n '...' || true)"
[ -n "$x" ] || die "the pool $POOL is absent. Run: just pool-up"
```

## `die` inside a pipeline stops only the subshell

`die` calls `exit`, and a function in a pipeline runs in a subshell. So a `die`
there ends the subshell, the reader gets empty input, and the person sees a
Python traceback instead of the message.

Call `need_api_key` and `need_project` **early**, at the top of the script,
never only inside a pipeline. Every script that reads Palette does this, and
each one says why.

## `UID` is readonly in bash

```text
bash: UID: readonly variable
```

`UID=x python3 -c '...'` fails. The helpers use `PEL_UID`. `shellcheck` does not
catch this.

## `virsh` tables have a header row

`virsh domiflist` and `virsh net-dhcp-leases` print a header, and awk with plain
field numbers matches it. `host-ip.sh` reported the address of a host as
`Protocol` until it matched on the shape of a MAC address instead of on a line
number.

## An interactive `gh` wrapper breaks `set -u`

A `gh` shell function is exported into child shells. One that reads `$GH_REPO`
with no default aborts under `set -u`, silently, when the standard error is
redirected.

Scripts call `command gh`, never a bare `gh`.

## A backgrounded `kubectl port-forward` outlives its shell

`dashboard.sh` cannot use `exec`: the kubeconfig sits in a temporary directory,
and the shell has to stay alive to remove it. A child then survives a signal
that the shell takes and the child does not. The orphan holds the local port and
answers there with a forward to a cluster that is gone.

Keep the pid, kill it in the `EXIT` trap, and test the port with `/dev/tcp`
**before** the recipe prints a URL, so the failure names the orphan.

## Never chmod a whole state directory

`TF_DATA_DIR` lives under the state directory and holds the provider binary. A
blanket `chmod 600` gives this on the next run:

```text
fork/exec .../terraform-provider-spectrocloud: permission denied
```

`protect_state` in `cluster.sh` uses `-maxdepth 1`.

## `systemctl list-units` lists the units that are LOADED

A service that is stopped and unloaded does not appear. A check built on that
command reports "not installed" while the unit file is still on disk, and
`svc.sh install` then refuses with "exists" for ever.

Test the **file**. `runner_units` in `lib.sh` does.

## libvirt does not refuse to remove an object that is in use

`virsh net-destroy` on a network that a running domain uses returns **0**. The
domain keeps running with a bridge that is gone: no address, no registration,
and no message anywhere.

An earlier `net-down.sh` tested the exit code for this, so that guard never
fired. `domains_using_network` and `domains_using_pool` in `lib.sh` do the test
that libvirt does not, and `FORCE=1` passes it.

## Do the root work before the object exists

`pool-up.sh` used to define the pool and then `sudo chown` its directory. On a
workstation with no cached password, that left a pool that was defined,
inactive, and unusable, and the next run reported "already defined" and failed
in the same place.

All of the sudo happens first now, and the script names the two commands to run
by hand when there is no terminal and no cached password.

## `rmdir` needs write permission on the PARENT

`/var/lib/libvirt/images` is `drwx--x--x root:root`. So `pool-down` cannot
remove its own pool directory, even though `pool-up` gave that directory to you.
The directory is traversable and not readable, so `[ -d ]` works and `ls` does
not.

Report the two reasons apart. "The directory still holds a file" is worth
saying. "The parent belongs to root" is not a fault, and a message that treats
it as one sends a person looking for a mistake that they did not make.

## Never hand libvirt a file inside the checkout

libvirt gives every file that a domain uses to the `libvirt-qemu` user, and it
does not give it back when the start fails. A seed ISO in the checkout would
therefore stop belonging to you, and the seed directory is mode 0700, so the
qemu user cannot enter it in the first place.

`host-up.sh` copies the seed into the storage pool and attaches that copy.
`host-down.sh` and `host-eject.sh` delete pool files. `seed-iso.sh` unlinks its
output before it writes, so a seed that libvirt captured can still be rebuilt
with no sudo.

## Test for a usable credential, not for the file

`infra-down` tested `[ -s "$(api_key_file)" ]`. A key given in the environment
is the documented way to give one for a single command, and it is the only way
that continuous integration gives one, so every CI run skipped the whole Palette
half of the layer **without saying so** and orphaned a host record for every
machine it deleted.

`have_api_key` tests both sources. Use it where a missing key is a condition to
report, and `need_api_key` where it is a reason to stop.

## A recipe must not wait for something that cannot happen

`hosts-wait` asked the API every 15 seconds for the whole `REGISTER_TIMEOUT`,
900 seconds, when there were no virtual machines at all.

It asks libvirt first now: a name with no domain and no record fails in a
second. It also counts `in-use` as registered, exactly as
`cluster.sh:require_ready_hosts` does, or a second run on a live cluster waits
the whole timeout for hosts that registered days before.

## A guard needs a test

Each rule on this page is a guard in a script, and a guard is one `if` away from
never firing again. When it stops, nothing says so: the recipe still returns 0.

`just test` runs the guards offline in about a second, and `just lint` runs it.
Add a test with a guard. See [Tests](./tests.md).

## The justfile

### A failing recipe prints its own message and nothing else

`set no-exit-message` drops the line that `just` adds after a failure:

```text
error: recipe `palette-hosts` failed on line 300 with exit code 1
```

That line names a line of the `justfile`. It helps somebody who edits the
justfile, it says nothing to somebody who is using the tooling, and it comes
last, so it stays on the screen while the correction scrolls away.

**So every `die` message must name the fix.** It is now the only thing that the
person sees. The exit code is unchanged, and the argument errors of `just`, such
as a wrong number of positional arguments, still print.

Boolean settings take the bare form. `set no-exit-message`, not
`set no-exit-message := true`, or `just --fmt --check` fails.

### `just` has no `state_directory()`

It has `config_directory()`, `data_directory()`, and `cache_directory()`. The
justfile builds the XDG state path by hand:

```just
{{#include ../../justfile:dirs}}
```

### A recipe must hold no default of its own

`just config` repeated every default from the `justfile`, one of them drifted,
and the recipe then reported a 60 GB control plane disk while the recipes built
a 100 GB one. The recipe passes every value that it computed, and `config.sh`
prints what it receives.

A workflow must not repeat one either. The e2e workflow held its own
`CLUSTER_NAME`, subnet, virtual address, and pod range, and they drifted on the
first change. `just ci-env` prints them, and the workflow reads that into
`GITHUB_ENV`.

### A parameter names a kind, not a position

`host-up host role="worker"`, `default-project project`, `test filter=""`. The
completion reads the recipe names from `just --summary` and the parameters from
`just --dump --dump-format json`, then completes by parameter **name**. It holds
no list of recipes, so a new recipe completes for free.

Keep a parameter named `host`, `project`, `role`, `action`, or `filter`, or add
the new kind to `_PEL_KINDS` in `scripts/bash-completion.sh`. Free text goes in
`_PEL_KINDS_FREE`. `scripts/lint-params.sh` fails the build on a name that the
completion does not know.

## The documentation

### mdBook does NOT fail on a missing anchor

It fails on a missing **file**. An include whose anchor was renamed renders as a
silent empty code block, which is exactly the rot that
[rule 5](./rules.md#5-the-documentation-includes-the-source) exists to prevent.
It happened here during the layer rename.

`scripts/lint-includes.sh` tests both halves of every include.

### Edit the template when you add a setting

`templates/project.env` is the file that `just new-project` fills in, and it
carries the anchors that this book includes. A new setting that does not reach
that file is a setting that the book does not describe.
