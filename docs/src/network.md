# The cluster network

The cluster uses a private NAT network. The virtual machines reach the internet, and
they reach each other. Nothing on your local network reaches them.

## The definition

`scripts/net-up.sh` reads this template, replaces the placeholders, and defines
the network.

```xml
{{#include ../../templates/network.xml:network}}
```

`@NAME@` becomes `$CLUSTER_NAME-net`, `@BRIDGE@` becomes `br-$CLUSTER_NAME`, and
`@SUBNET@` becomes `$CLUSTER_SUBNET`.

The bridge name is a Linux interface name, so `CLUSTER_NAME` takes 12 characters at
most. See [Settings](./settings.md#the-cluster-size).

## Address plan

| Range | Use |
| --- | --- |
| `.1` | The gateway on the workstation. |
| `.2` to `.49` | Free. Use these for a fixed address. |
| `.50` to `.199` | The DHCP pool for the edge hosts. |
| `.200` to `.254` | Free. |

The free ranges hold an address for a registry mirror or a control plane VIP.
The DHCP pool never gives out those addresses.

## Commands

```bash
just net-up      # create and start the network
just net-down    # stop and remove the network
just ip <host>   # show the address of one host
just ls          # show the state and address of every host
```

`just ip` reads the DHCP lease. The stock cloud image does not run the QEMU
guest agent, so `virsh domifaddr` returns nothing. The lease is the reliable
source.

## A subnet conflict

`just net-up` fails if `$CLUSTER_SUBNET` conflicts with another network. To see the
networks on your workstation:

```bash
virsh net-list --all
virsh net-dumpxml default
```

Change `CLUSTER_SUBNET` in the project file to a free subnet. Then run
`just net-down` and `just net-up`.

## A second cluster

Change `CLUSTER_NAME` and `CLUSTER_SUBNET` in a second project file. Every object gets
the new prefix, so the two clusters do not conflict.
