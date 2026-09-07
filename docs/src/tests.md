# Tests

| Recipe | Question | Needs |
| --- | --- | --- |
| `just test` | Do the guards and the readers operate correctly? | Nothing. |
| `just cluster-verify` | Does a real cluster operate correctly? | A cluster. |

`just lint` runs the first recipe. The e2e workflow runs the second recipe
against a cluster that it builds and then removes. See
[Continuous integration](./ci.md).

## just test

```just
{{#include ../../justfile:test}}
```

```bash
just test                # all test files
just test seed           # the files with "seed" in the name
```

The tests use no libvirt, no Palette tenant, no network, and no file outside a
temporary directory. Thus they operate in a new checkout, and they operate on
the hosted runner. They take approximately one second.

## What the tests examine

The test files are in `tests/`:

| File | Subject |
| --- | --- |
| `tests/lib.test.sh` | The tooling directories and the guards in `scripts/lib.sh`. |
| `tests/palette-lib.test.sh` | The functions that read a Palette answer. |
| `tests/seed-iso.test.sh` | The seed ISO: the values, the file modes, and the refusals. |

The tests examine the guards. A guard is a test in a script that refuses a
condition. Each guard in this repository prevents a known failure:

- A cluster name that libvirt accepts, but Palette refuses. Palette refuses the
  name some minutes after the recipes build the machines with that name.
- A pod range that contains the cluster subnet. Then all nodes become Ready,
  `kubectl` operates, and Palette stays in `Provisioning`.
- A cluster list that counts a deleted cluster. Then `just infra-down` refuses
  after a correct `just cluster-down`.
- A seed value with an apostrophe in it, or a `vip.skip` value that is not a
  boolean.

A guard can stop its operation after a small change to one `if` statement. The
recipe then returns 0 and does not refuse the condition. The failure occurs
later, and the message does not identify the cause. Thus each guard needs a
test.

## How the tests examine the Palette functions

Each test replaces the `api` function with a function that prints a recorded
answer. The test also writes the request to a log file. The reader function
then operates on the data that the tenant sends, and the test examines the
result.

The log file is also a test. `project_list` and `edge_host_list` use POST,
because Palette does not answer a GET on those paths. A reader function that
uses GET again receives HTTP 405. There is no other symptom on the workstation.

## How to write a test

A test file includes `tests/assert.sh` and then calls the assertions. The test
file counts nothing, and it sets no `trap`. The EXIT trap in `assert.sh` prints
the totals and sets the exit code.

```bash
{{#include ../../tests/assert.sh:assertions}}
```

Use `refuses_with` for a guard. A refusal in this repository names the
correction, thus the message is part of the behaviour:

```bash
refuses_with "13 characters: the bridge name is too long" \
	"network device takes 15" require_cluster_name abcdefghijklm
```

Use `tmpdir` to make a temporary directory. The EXIT trap removes each one.

## What the tests do not examine

The tests do not examine libvirt or the tenant. This is deliberate. A test that
needs libvirt or a tenant does not operate in a new checkout. Persons do not run
a test suite that fails for that reason.

`just cluster-verify` examines the other half. It examines a cluster that
operates: the nodes, the pod range, the packs, and DNS. The e2e workflow runs it
each night against a new cluster.
