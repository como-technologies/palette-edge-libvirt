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

`scripts/seed-iso.sh` replaces each placeholder with a value from `.env`. The
script passes the values in the environment, not in the program text, so a value
with a quotation mark or a backslash is safe.

The script tests the result. If a placeholder stays in the file, or the token is
empty, or `stylus.vip.skip` is not a boolean, the script stops with an error.

## The installation

```yaml
{{#include ../../templates/user-data.tmpl.yaml:install}}
```

The script comes from the agent-mode releases:

```bash
{{#include ../../scripts/seed-iso.sh:agenturl}}
```

Set `PALETTE_AGENT_VERSION` in `.env` to pin a version. An empty value gives the
latest release.

## Build a seed

```bash
just seed <host>    # one host
just seed-all       # every host in the topology
just seed-clean     # delete every seed ISO
```

Each ISO goes to `seeds/` with the file mode 0600. The directory has the mode
0700. Git ignores the directory.

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

`just remove-project` refuses while a project holds a host, so the records go
first.

## Rotate the token

1. Make a new token in Palette at **Tenant Settings**, then
   **Registration Tokens**.
2. Put the new token in `.env`.
3. Run `just seed-clean`, then `just seed-all`.
4. Rebuild the hosts with `just cluster-down` and `just cluster-up`.
5. Delete the old token in Palette.
