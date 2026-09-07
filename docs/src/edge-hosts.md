# Host registration

A host registers itself with your Palette tenant at the first boot. The seed ISO
gives it the necessary values.

## The seed ISO

`scripts/seed-iso.sh` renders one template for each host and writes the result
into an ISO. The ISO volume label is `CIDATA`:

```bash
{{#include ../../scripts/seed-iso.sh:mkiso}}
```

The virtual machine gets this ISO as a CD-ROM. cloud-init looks for a volume
with the label `CIDATA` and reads `user-data` and `meta-data` from it.

## The packages

The agent install script tests for these commands and stops without them:

```yaml
{{#include ../../templates/user-data.tmpl.yaml:packages}}
```

## The site configuration

cloud-init writes this file, and the agent reads it:

```yaml
{{#include ../../templates/user-data.tmpl.yaml:siteconfig}}
```

`scripts/seed-iso.sh` replaces each placeholder with a value from the project
file. The script passes the values in the environment, not in the program text,
so a value with a quotation mark or a backslash is safe.

The script tests the result. If a placeholder stays in the file, or the token is
empty, or `stylus.vip.skip` is not a boolean, the script stops with an error.

### The values have two classes, and the template must not quote either

Look at the placeholders above: not one of them carries a quotation mark. That
is deliberate, and adding one breaks the seed.

A **scalar** goes through `json.dumps`, which writes a double-quoted YAML
scalar with the correct escapes. YAML 1.2 accepts JSON, so a project named
`O'Brien's Lab` and a token that holds a `"` or a `\` both survive.

Two values go in **raw**, with no quotation marks added:

| Placeholder | Why raw |
| --- | --- |
| `@PALETTE_VIP_SKIP@` | it must stay a YAML boolean. `skip: "false"` is a string, and the agent reads it as one. |
| `@AGENT_SCRIPT_URL@` | it already sits inside quotation marks in the template. |

A quotation mark in the template gives `""false""` for the first and a broken
command for the second. `just test` holds this in place: it renders a seed with
an apostrophe in the project name and a quotation mark in the token, and it
tests that the boolean is still a boolean. See [Tests](./tests.md).

### Two files hold the token, not one

The ISO holds it, and so does the rendered `user-data` that the ISO is built
from. An earlier version protected the ISO only and left a readable copy in
`~/.local/share/palette-edge-libvirt/build/seed-<host>/user-data`.

Both directories are mode 0700 now and both files are mode 0600. `just seed-clean`
removes both, and `just remove-project` removes the seeds of the project that it
removes.

## The installation

```yaml
{{#include ../../templates/user-data.tmpl.yaml:install}}
```

The script comes from the agent-mode releases:

```bash
{{#include ../../scripts/seed-iso.sh:agenturl}}
```

Set `PALETTE_AGENT_VERSION` in the project file to pin a version. An empty
value gives the latest release.

## Build a seed

```bash
just seed <host>    # one host
just seed-all       # every host in the topology
just seed-clean     # delete every seed ISO
```

Each ISO has the file mode 0600, and the seed directory has the mode 0700. The
directory is outside the checkout. See
[The tooling directories](./directories.md).

## After the registration

Eject the seed ISO. The host then keeps no copy of the token:

```bash
just host-eject <host>
```

## Test the registration

```bash
just palette-hosts
```

The recipe reads your tenant through the API and lists the hosts in your
project. It also tests that `PALETTE_PROJECT` exists, and it names the correct
projects if the value is wrong.

## Remove a host

```bash
just host-down <host>        # the virtual machine and its disk
just host-deregister <host>  # the record in Palette
```

The two recipes are separate on purpose. `host-down` touches the workstation
only, so it is safe to run at any time. `host-deregister` changes your tenant.

Remove the record when you rebuild a host and want a true test. The uid of an
edge host is its name, so a rebuilt host takes the old record again. The old
record then looks like a new registration, and it is not.

**A host belongs to one cluster, and a virtual machine is never reused.** That
is what makes `just infra-down` safe to remove every host record with the
machines: a record whose machine is gone is garbage. Rebuild rather than repair.

`just remove-project` refuses while a project holds a host, so the records go
first.

## Rotate the token

1. Make a new token in Palette at **Tenant Settings**, then
   **Registration Tokens**.
2. Put the new token in the project file.
3. Run `just seed-clean`, then `just seed-all`.
4. Rebuild the hosts with `just infra-down` and `just infra-up`.
5. Delete the old token in Palette.
