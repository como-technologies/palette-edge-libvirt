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

`PALETTE_PROJECT` is the value that causes the most lost time. The name is case
sensitive, and a wrong name gives no error. Test it before you make any host:

```bash
just palette-projects
```

## The Palette agent

```bash
{{#include ../../.env.example:agent}}
```

## The host image

The lab uses the stock Ubuntu cloud image. It builds no custom image.

```bash
{{#include ../../.env.example:image}}
```

Keep `UBUNTU_IMAGE_URL` empty. `just image-fetch` then builds the URL from the
release:

```bash
{{#include ../../scripts/image-fetch.sh:url}}
```

`just image-fetch` also reads the published `SHA256SUMS` file and tests the
image against it. A image that does not match is deleted and downloaded
again.

## Topology

These values set the number of nodes and the size of each node.

```bash
{{#include ../../.env.example:topology}}
```

`LAB_NAME` is the prefix of every libvirt object. The default prefix `pe` gives
the network `pe-net`, the pool `pe-pool`, and the domains `pe-cp-1`, `pe-wk-1`,
and `pe-wk-2`. Change the prefix to run a second lab at the same time.

The Palette agent needs 2 CPU, 8 GB of memory, and 100 GB of storage for each
host. The default values give that minimum or more.

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
