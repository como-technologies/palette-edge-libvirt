# Edge host registration

An edge host registers itself with your Palette tenant. The seed ISO gives it
the necessary values.

## The seed ISO

`scripts/seed-iso.sh` renders one template for each host and writes the result
into an ISO. The ISO volume label is `CIDATA`:

```bash
{{#include ../../scripts/seed-iso.sh:mkiso}}
```

The virtual machine gets this ISO as a second CD-ROM. The Edge installer looks
for a volume with the label `CIDATA` and reads the `user-data` file from it.

## The registration block

This is the part of the template that does the registration:

```yaml
{{#include ../../templates/user-data.tmpl.yaml:stylus}}
```

`scripts/seed-iso.sh` replaces each placeholder with a value from `.env`. The
script passes the values in the environment, not in the program text. A token
with a quote, a backslash, or an ampersand is safe.

The script also tests the result. If a placeholder stays in the file, the script
stops with an error.

## The installation block

```yaml
{{#include ../../templates/user-data.tmpl.yaml:install}}
```

The installer writes to `/dev/vda`, the first virtio disk. Then it reboots. See
[Architecture](./architecture.md#why-the-boot-order-matters) for the boot order.

## Build a seed

```bash
just seed pe-cp-1   # one host
just seed-all       # every host in the topology
just seed-clean     # delete every seed ISO
```

Each ISO goes to `seeds/` with the file mode 0600. The directory has the mode
0700. Git ignores the directory.

## After the registration

Eject both ISO files. The host then keeps no copy of the token:

```bash
just host-eject pe-cp-1
```

## Remove a host

```bash
just host-down pe-cp-1
```

This recipe removes the virtual machine and its disk. It does not remove the
Edge Host entry in Palette. Remove that entry in Palette at **Clusters**, then
**Edge Hosts**.

## Rotate the token

1. Make a new token in Palette at **Tenant Settings**, then
   **Registration Tokens**.
2. Put the new token in `.env`.
3. Run `just seed-clean`, then `just seed-all`.
4. Rebuild the hosts with `just cluster-down` and `just cluster-up`.
5. Delete the old token in Palette.
