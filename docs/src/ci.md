# Continuous integration

Two kinds of test run against this repository.

| Test | Runner | Trigger | What it does |
| --- | --- | --- | --- |
| `ci`, `docs` | GitHub hosted | every push and pull request | `just lint`, which runs `just test`, and the book build |
| `e2e` | your workstation | push to `main`, and by hand | a real cluster, tested and removed |

The hosted tests need no cluster, so they run on a machine that GitHub throws
away. The end to end test needs KVM, libvirt, and a Palette tenant, so it runs
on the workstation.

## The runner is a process, not a virtual machine

The runner is a systemd service that runs as its own user on the workstation. It
makes the cluster machines directly with libvirt, so the nodes run on the metal
and no memory waits idle for a job.

## The runner uses the session daemon

libvirt has two connections, and the difference decides what a compromised
runner can reach.

| | `qemu:///system` | `qemu:///session` |
| --- | --- | --- |
| The daemon runs as | root | the runner |
| A domain may open | any file on the workstation | the files the runner can open |
| Access comes from | the `libvirt` group | owning the session |

The system socket is `root:libvirt` and `libvirtd.conf` sets `auth_unix_rw` to
`none`, so **a member of the `libvirt` group drives a daemon that runs as
root**. Such a member defines a domain whose disk is `/dev/nvme0n1`, starts it,
and reads and writes every file on the workstation: your keys, your tokens,
`/etc/shadow`. The `libvirt` group is the same as root, and no sudoers file
changes that.

The runner is therefore **not in the `libvirt` group**. It uses the session
daemon, which runs as the runner and opens only what the runner can open. A
build that goes wrong reaches one unprivileged account.

Your own lab keeps `qemu:///system`, which is simpler and needs none of the
setup below. Session mode is the CI path.

## What a session cannot do for itself

Three things need root, so `just runner-setup` does each one time.

**The network.** A session makes no network: a bridge, NAT, and dnsmasq all need
root. So root makes one system network, `cilab-net`, and the session domains
attach to its bridge. The network still brings the subnet, the DHCP server, and
the address that kube-vip claims, so nothing else changes.

**The bridge helper.** A session domain reaches the bridge through
`qemu-bridge-helper`. Ubuntu ships that program with no setuid bit and no
capability, so root gives it `cap_net_admin` and writes `/etc/qemu/bridge.conf`.
That file names the bridges any account may join, and it names `br-cilab` only.

**Nothing else.** The pool lives in the home directory of the runner, so no
directory under `/var/lib/libvirt` is needed and no recipe asks for a password.

That bridge causes two more differences. The scripts contain both of them:

- A session domain attaches with `--network bridge=br-cilab`. It does not use
  `--network network=cilab-net`. The network belongs to the system connection,
  and a session cannot name it. The two connections share the bridge. The
  dnsmasq server of the system network answers DHCP on the session interfaces.
- The DHCP lease table also belongs to the system connection, and a session
  cannot read it. Thus `host-ip.sh` reads `ip neigh` on the bridge. It gets the
  same answer.

The scripts read `LIBVIRT_DEFAULT_URI` and take the right path for each: see
`libvirt_session` and `pool_target` in `scripts/lib.sh`.

{{#include ../../scripts/lib.sh:session}}

The runner user holds **no sudo**, and with the session daemon that statement
now means something: it is not root by another route either.

## The lab of CI is not your lab

Two labs share one workstation when the name and the subnet both differ.

| Setting | Yours | CI |
| --- | --- | --- |
| `CLUSTER_NAME` | from `just new-project` | `cilab` |
| `CLUSTER_SUBNET` | 192.168.140 to 192.168.199 | 192.168.210 |

The CI subnet sits **outside** the range that `just new-project` allocates. A
teardown of the CI lab therefore never frees an address that a lab of yours
could take, and the reverse is true as well.

The two labs together need 32 vcpu, which is every thread of the reference
workstation. Expect to notice a CI run while you use a lab of your own.

## The repository is public

A self-hosted runner executes code on a personal workstation. Name what is at
risk before naming the gates: a shell as the runner account, and the Palette API
key, which carries every permission of the person who made it.

Four gates stand between an outsider and that.

1. **The workflow names no `pull_request` trigger.** A fork cannot fire `push`,
   or `workflow_dispatch`, so a fork has no path to the workstation.
2. **A fork pull request needs approval.** On a `pull_request` event GitHub runs
   the workflow files of the pull request, not the ones on `main`, so a pull
   request can add a workflow of its own that names the runner. The approval
   setting is what stops it.
3. **`main` is protected.** A pull request needs one approval and the `lint`
   check before it reaches `main`. Read the next section before you count this
   one: it is weaker than it looks.
4. **The `lab` environment admits protected branches only**, and it holds the
   Palette key, so a job on a side branch receives no credentials.

`just ci-setup` makes all four.

### Write access is the boundary, and gate 3 is not

Gate 3 does not give the protection that its description suggests.
`enforce_admins` is false. Thus an administrator pushes to `main` with no
review, and the runner executes that code.

A value of `enforce_admins: true` does not correct this. **Each account with
write access to this repository is an administrator.** An administrator removes
a protection rule with one API call. A rule that applies only to the persons who
can delete it applies to nobody. It prevents an accidental push. It does not
prevent a deliberate one.

A branch and a pull request also add no protection alone. A person who can merge
can merge the code that the same person wrote. The required approval gives the
check by a second person. That check applies only to a writer who is not an
administrator, and there is no such writer here.

Thus there is no technical control behind write access. **Each person who can
put a commit on `main` runs code on this workstation.** The control is the list
of persons with that access. Examine that list. Keep it short. Write access to
this repository gives a shell on the machine:

```bash
gh api repos/{owner}/{repo}/collaborators   --jq '.[] | "\(.login) \(.role_name) push=\(.permissions.push)"'
```

Two settings each prevent a part of this condition. Each setting has a cost:

| Change | Closes | Costs |
| --- | --- | --- |
| `enforce_admins: true` | an administrator's **accidental** push. Not a deliberate one. | every change needs a pull request |
| a required reviewer on `lab` | a run that nobody approved, whatever reached `main` | every run waits for a click |

The second setting gives more protection. It applies to the **run** and not to
the code. An administrator must change the setting to remove the approval step.

`just ci-setup` sets neither one. This repository is a laboratory on one
workstation. That decision is about cost. It is not a statement that the gates
are complete.

### Gate 2 gives the most protection

It is the only path to the runner that needs **no write access**. On a
`pull_request` event, GitHub runs the workflow files of the pull request. It
does not run the files on `main`. Thus a pull request can add a new workflow
that names the runner.

The default policy is `first_time_contributors`. That value applies to the first
time **only**. After a maintainer merges one pull request from a person, that
person runs a workflow with no approval. Thus `just ci-setup` sets
`all_external_contributors`.

### What limits the damage

The gates above prevent access. These conditions limit the damage:

- The runner has **no sudo** permission, and it is **not** in the `libvirt`
  group. libvirt operates on `qemu:///session`. Thus an attack reaches one
  account with no privileges, and not the root account.
- The Palette key goes to the job in the environment. It does not become a file.
  Thus a run leaves no credential on the workstation.
- The key is a **tenant** credential with each permission of its owner. The
  workstation does not limit that permission. Make a new key if a run shows an
  incorrect condition.

## No third-party actions

The end to end job uses none. A third-party action on a mutable tag runs on your
workstation with no review, and that is the same exposure as an unreviewed
merge. The job takes the code with `git`, and every tool it needs is a recipe of
this repository.

The hosted `ci` and `docs` jobs still use actions. They run on a machine that
GitHub throws away, so a compromise there reaches nothing of yours.

## Prepare the workstation

```bash
just runner-setup     # the user, the groups, the pool directory, and cargo
just runner-up        # the runner and its systemd service
just ci-setup         # protect main, make the lab environment, store the key
just runner-status    # the service here, and the record in GitHub
```

`just runner-setup` needs root one time. It makes the user, puts it in the `kvm`
group and takes it out of `libvirt`, makes the system network of the CI lab,
gives `qemu-bridge-helper` its capability, and allows `br-cilab`.

It also gives the runner its own `just`. `cargo` installs it, exactly as the
hosted workflow installs mdBook, because the `just` in your home directory
belongs to you and the Ubuntu package is too old to read this justfile.

{{#include ../../justfile:runner}}

## Remove it

Every recipe above has a twin, in the reverse order:

```bash
just ci-setup-undo    # the lab environment and the protection of main
just runner-down      # the service, the registration, and the files
just runner-setup-undo # the user and the pool directory
```

`just runner-down` takes the runner out of GitHub as well. A runner that loses
its files without that step stays in the repository as an offline runner, and
the name is then taken.

## What the job does

```
just nuke            remove anything that an earlier run left
just new-project     a project for this run, named after the run
just infra-up        the machines, and every host registers
just cluster-up      the profile and the cluster
just cluster-verify  the test suite
just nuke            always, so a failed run leaves nothing
```

The Palette key reaches the job in the environment and never becomes a file, so
a run leaves no credential on the workstation.

The teardown is the isolation. A host cannot roll back to a snapshot the way a
virtual machine can, so cleanliness comes from the recipes, and those are safe
to run in any order. See [Project rules](./rules.md).

## What it tests

`just cluster-verify` is the test suite. `just cluster-up` returns 0 when
Palette reports that it made the cluster, and that is not the same as a cluster
that operates.

| Test | Why |
| --- | --- |
| the API server answers | the virtual address is claimed |
| every node is Ready, and the count matches | the machines joined |
| every node runs the pinned version | the profile and the cluster agree |
| every `podCIDR` sits inside `POD_CIDR` | the pack default was replaced |
| the pod range holds no address of the cluster subnet | Calico gives no NAT inside its own pool |
| Calico and CoreDNS pods are Ready | the network packs operate |
| a StorageClass is the default one | a claim can bind |
| a pod resolves a name | the test that the others cannot replace |

The last one is there for a reason. A pod range that holds the cluster subnet
gives a cluster where every node is Ready, `kubectl` answers, and no pod
resolves a name. Every test above it passes on that cluster. See
[The cluster profile](./cluster-profile.md).

## How long a build takes

The job is the measurement. It builds a whole cluster on every push to `main`
on the reference workstation, from the pins that the `justfile` holds now:

```bash
just ci-times            # the last 3 successful runs, step by step
CI_RUNS=10 just ci-times # a longer history
```

```text
  step                                           run 1     run 2     run 3       mean
  Make the machines                              2m57s     2m58s     2m58s      2m57s
  Make the cluster                              12m00s    13m43s     9m34s     11m45s
  Test the cluster                                  6s        4s        5s         5s
  Remove everything                                54s       54s       51s        53s
  whole job                                     16m03s    17m46s    13m35s     15m48s
```

`just cluster-up` uses almost all of the time. In that recipe, almost all of
the time is a wait. Palette installs the packs on each node. The difference
between the runs comes from the tenant, and not from the workstation.

This book had a table of times from a manual measurement. That table became
incorrect after the first change to the pinned versions. An add-on profile made
`cluster-up` approximately two times longer. No test found the error, because a
test cannot examine a number in a document.

The recipe reads the pipeline. Thus the answer is always current, and there is
no table to maintain. The recipe reads only the data that GitHub recorded. It
needs `gh` and its credentials, and it changes nothing.

## Pin the runner again

The runner archive carries a pinned checksum, and that is what makes it safe to
run on the workstation. To move to a new release:

```bash
just runner-pin
```

The recipe prints the two lines to put in the justfile. Change them, then run
`just runner-down` and `just runner-up`.

## What this does not do

A runner that a signal kills runs no teardown, not even the step that always
runs. The Palette project and its registration token then stay in the tenant,
and a token that names a project stops that project from being deleted.

`just palette-projects` and `just palette-tokens` show them, and
`just remove-project <name>` removes one.
