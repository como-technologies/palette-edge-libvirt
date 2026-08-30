# Configure the tenant

Two commands configure the lab.

```bash
just api-key-set            # store your Palette API key, one time
just new-project pe-thelio  # make the project and write its file
```

The first command reads the key without an echo and writes it to one file
outside the checkout. The second command makes the project in your tenant,
makes a registration token for it, writes `envs/pe-thelio.env`, and points
`.env` at that file.

There is nothing else to fill in. To see the result:

```bash
just config
```

That recipe prints the length of the token, never its value.

## What the two commands produce

| Value | Where it comes from |
| --- | --- |
| `PALETTE_ENDPOINT` | The endpoint you use. The default is `api.spectrocloud.com`. |
| `PALETTE_PROJECT` | The project name that you gave. |
| `PALETTE_EDGE_TOKEN` | The token that `new-project` made for that project. |
| `LAB_NAME` | The project name, shortened. A number is added if the prefix is in use. |
| `LAB_SUBNET` | The first free subnet from 192.168.140 to 192.168.199. |
| The API key | `~/.config/palette-edge-libvirt/api-key`, outside the checkout. |

The API key is **not** in the project file. A key carries every permission of
its owner, so it is a tenant credential. `just remove-project` must not delete
it. See [Projects](./projects.md).

There is **no default project**. A tenant need not have a project called
`Default`, and a tenant can delete that one. A recipe that guesses a project
name sends hosts to the wrong place, and Palette gives no error when it does.
Every recipe that needs the name therefore stops without it.

## Change the lab size

Edit `envs/<project>.env`. These values set the number of nodes and the size of
each node:

```bash
{{#include ../../.env.example:topology}}
```

The Palette agent needs 2 CPU, 8 GB of memory, and 100 GB of storage for each
host. These values give that minimum or more.

`LAB_NAME` is the prefix of every libvirt object. A lab named `pethelio` gives
the network `pethelio-net`, the pool `pethelio-pool`, and the domains
`pethelio-cp-1`, `pethelio-wk-1`, and `pethelio-wk-2`.

## Change the host image

The lab uses the stock Ubuntu cloud image. It builds no image.

```bash
{{#include ../../.env.example:image}}
```

Keep `UBUNTU_IMAGE_URL` empty. `just image-fetch` then builds the URL from the
release:

```bash
{{#include ../../scripts/image-fetch.sh:url}}
```

`just image-fetch` also reads the published `SHA256SUMS` file and tests the
image against it. An image that does not match is deleted and downloaded again.

## Change the agent settings

```bash
{{#include ../../.env.example:agent}}
```

## Change the network

```bash
{{#include ../../.env.example:libvirt}}
```

`new-project` chooses a free subnet, so you rarely change this. Use a subnet
that no other libvirt network uses. The default libvirt network usually uses
`192.168.122.0/24`. To see the networks on your workstation, run
`virsh net-list --all`.

## One command, one value

Each value is also a normal environment variable. To change one value for one
command, set the value on the command line:

```bash
WORKER_COUNT=3 just cluster-up
```

## Every value

`.env.example` documents every variable. `just new-project` writes a file from
it, so the two never disagree.
