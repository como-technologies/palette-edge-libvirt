# Tests

This repository has two kinds of test, and they answer different questions.

| Recipe | Question | Needs |
| --- | --- | --- |
| `just test` | Do the guards and the readers behave? | Nothing. |
| `just cluster-verify` | Does a real cluster work? | A cluster. |

`just lint` runs the first. The nightly e2e workflow runs the second, against a
cluster that it builds and removes. See [Continuous
integration](./ci.md).

## just test

```just
{{#include ../../justfile:test}}
```

```bash
just test                # every test file
just test seed           # the files whose name holds "seed"
```

The tests reach **nothing**: no libvirt, no Palette tenant, no network, and no
file outside a temporary directory. So they run on a fresh checkout, they run on
the hosted runner, and they finish in about a second.

## What they cover

The tests are in `tests/`, one file for each subject:

| File | Subject |
| --- | --- |
| `tests/lib.test.sh` | The tooling directories and the guards of `scripts/lib.sh`. |
| `tests/palette-lib.test.sh` | The readers that turn a Palette answer into a value. |
| `tests/seed-iso.test.sh` | The seed ISO: the render, the modes, and the refusals. |

They test the guards. Each guard in this repository was written after a failure
that cost an afternoon:

- a cluster name that libvirt accepts and Palette refuses, minutes after the
  machines were built under that name
- a pod range that holds the cluster subnet, which leaves Palette in
  `Provisioning` for ever with every node Ready
- a cluster list that counts a deleted cluster, so `just infra-down` refuses
  for ever after a correct `just cluster-down`
- a seed value with an apostrophe in it, or a `vip.skip` that stopped being a
  boolean

A guard is one `if` away from never firing again, and it fails silently when it
stops: the recipe still returns 0, and the cost arrives an hour later. A guard
that no test exercises is a comment.

## How the Palette readers are tested with no tenant

Each test replaces `api` with a function that prints a recorded answer and
writes the request to a log. The reader then runs against the shape that the
tenant really returns, and the test reads what the reader did with it.

That log is a test of its own. `project_list` and `edge_host_list` are POSTs
because Palette stopped answering a GET on those paths, and a reader that goes
back to a GET returns HTTP 405 with no local symptom at all.

## Writing a test

A test file sources `tests/assert.sh` and calls assertions. It keeps no count
and it sets no `trap`: the EXIT trap of that file prints the tally and sets the
exit code.

```bash
{{#include ../../tests/assert.sh:assertions}}
```

`refuses_with` is the one to reach for. A refusal in this repository names the
correction, so the message is part of the behaviour and not decoration:

```bash
refuses_with "13 characters: the bridge would not fit" \
	"network device takes 15" require_cluster_name abcdefghijklm
```

Use `tmpdir` for a temporary directory. The report trap removes every one.

## What they do not cover

Anything that needs libvirt or a tenant. That is deliberate: a test that needs
either one does not run on a fresh checkout, and a test suite that people skip
protects nothing.

`just cluster-verify` covers the other half. It tests a live cluster — the
nodes, the pod range, the packs, and DNS — and the e2e workflow runs it against
a cluster that it builds every night.
