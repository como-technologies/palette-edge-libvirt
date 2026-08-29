# Configure the tenant

All configuration goes in a `.env` file. Git ignores this file, because it holds
your registration token.

```bash
cp .env.example .env
```

Then edit `.env`. To see the effective values at any time, run `just config`.
That recipe prints the token status only. It never prints the token.

## Palette values

You get these values from your Palette tenant.

```bash
{{#include ../../.env.example:palette}}
```

To find the registration token, open Palette. Go to **Tenant Settings**, then
**Registration Tokens**. Make a token, or use an existing token.

## Installer media

```bash
{{#include ../../.env.example:installer}}
```

Keep `EDGE_INSTALLER_URL` empty for the standard installer ISO. `just iso-fetch`
then builds the URL from the version:

```bash
{{#include ../../scripts/iso-fetch.sh:url}}
```

Your tenant can also give you a direct link. Open Palette, go to **Clusters**,
then **Edge Hosts**, then **Add Edge Host**. Put that link in
`EDGE_INSTALLER_URL`.

## Topology

These values set the number of nodes and the size of each node.

```bash
{{#include ../../.env.example:topology}}
```

`LAB_NAME` is the prefix of every libvirt object. The default prefix `pe` gives
the network `pe-net`, the pool `pe-pool`, and the domains `pe-cp-1`, `pe-wk-1`,
and `pe-wk-2`. Change the prefix to run a second lab at the same time.

## libvirt

```bash
{{#include ../../.env.example:libvirt}}
```

Use a subnet that no other libvirt network uses. The default libvirt network
usually uses `192.168.122.0/24`. To see the networks on your workstation, run
`virsh net-list --all`.

## One command, one value

Each value is also a normal environment variable. To change one value for one
command, set the value on the command line:

```bash
WORKER_COUNT=3 just cluster-up
```
