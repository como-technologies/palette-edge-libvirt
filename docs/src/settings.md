# Settings

This page describes each value in `envs/<project>.env`.
[The project layout](./project-layout.md) describes the files themselves and
which values `just new-project` chooses.

`just new-project` writes a good value for every setting, so you change a value
only when you want a different lab. To see the values that the recipes use now,
run `just config`.

## The two credentials

The API key is **not** in the project file. It is a tenant credential, and it
lives at `~/.config/palette-edge-libvirt/api-key`:

```bash
just api-key-set      # store the API key
just api-key-status   # report its length only
just api-key-clear    # delete it
```

The registration token **is** in the project file. A token registers hosts into
one project, so it belongs to that project and dies with it.

## There is no default project

A tenant need not have a project called `Default`, and a tenant can delete that
one. A recipe that guesses a project name sends hosts to the wrong place, and
Palette gives no error when it does. The host starts, the agent runs, and the
host never shows in the console.

Every recipe that needs the name therefore stops without it.
`just palette-projects` is the one exception, because that recipe finds the
name.

## The lab size

```bash
{{#include ../../.env.example:topology}}
```

The Palette agent needs 2 CPU, 8 GB of memory, and 100 GB of storage for each
host. These values give that minimum or more.

`LAB_NAME` is the prefix of every libvirt object. A lab named `pethelio` gives
the network `pethelio-net`, the pool `pethelio-pool`, and the domains
`pethelio-cp-1`, `pethelio-wk-1`, and `pethelio-wk-2`.

Two labs run at the same time if `LAB_NAME` and `LAB_SUBNET` both differ.

## The host image

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
Canonical rebuilds the current image, so an old cached image can be correct but
different.

## The agent

```bash
{{#include ../../.env.example:agent}}
```

`PALETTE_VIP_SKIP` controls kube-vip. A lab with one control plane node does not
need a virtual address. Set the value to `false` for more than one control plane
node, then give the VIP in Palette. Use an address from the free range of the
lab subnet, for example `192.168.140.10`. See
[The lab network](./network.md#address-plan).

## The network

```bash
{{#include ../../.env.example:libvirt}}
```

`new-project` chooses a free subnet, so you rarely change this. Use a subnet
that no other libvirt network uses. The default libvirt network usually uses
`192.168.122.0/24`. To see the networks on your workstation, run
`virsh net-list --all`.

## The Palette values

```bash
{{#include ../../.env.example:palette}}
```

## One command, one value

Each value is also a normal environment variable. To change one value for one
command, set the value on the command line:

```bash
WORKER_COUNT=3 just cluster-up
LAB_NAME=pe just infra-down
```

The second example operates on a lab whose environment file is gone.

## Every value

`.env.example` documents every variable. `just new-project` writes a file from
it, so the two never disagree. This page includes the same file, so it cannot
disagree either.
