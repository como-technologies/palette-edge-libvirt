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
| `.2` to `.9` | Free. Use these for a fixed address. |
| `.10` | `CLUSTER_VIP`, the control plane endpoint. kube-vip claims it. |
| `.11` to `.49` | Free. Use these for a fixed address. |
| `.50` to `.199` | The DHCP pool for the edge hosts. |
| `.200` to `.254` | Free. |

The DHCP pool never gives out an address below `.50`, so `CLUSTER_VIP` and any
other fixed address are safe there. `just new-project` writes the `.10` address
of the subnet that it allocated. See
[The virtual address](./cluster-profile.md#the-virtual-address).

## The three ranges of a cluster

The cluster network is one of three ranges, and no two of them may overlap:

| Range | Default | Set by |
| --- | --- | --- |
| The cluster network | `CLUSTER_SUBNET`, `192.168.140.0/24` | `just new-project` |
| The pods | `POD_CIDR`, `10.244.0.0/16` | the project file |
| The services | `192.169.0.0/16` | the `edge-k8s` pack |

`POD_CIDR` must also hold no address of your workstation. The pack default for
the pods is `192.168.0.0/16`, which holds every cluster subnet and most home
networks, so the project file replaces it. See
[The pod range](./cluster-profile.md#the-pod-range).

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
