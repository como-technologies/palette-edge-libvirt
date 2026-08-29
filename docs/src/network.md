# The lab network

The lab uses a private NAT network. The virtual machines reach the internet, and
they reach each other. Nothing on your local network reaches them.

## The definition

`scripts/net-up.sh` reads this template, replaces the placeholders, and defines
the network.

```xml
{{#include ../../templates/network.xml:network}}
```

`@NAME@` becomes `$LAB_NAME-net`. `@SUBNET@` becomes `$LAB_SUBNET`.

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
just ip pe-cp-1  # show the address of one host
just ls          # show the state and address of every host
```

`just ip` reads the DHCP lease. The edge images do not run the QEMU guest agent,
so `virsh domifaddr` returns nothing. The lease is the reliable source.

## A subnet conflict

`just net-up` fails if `$LAB_SUBNET` conflicts with another network. To see the
networks on your workstation:

```bash
virsh net-list --all
virsh net-dumpxml default
```

Change `LAB_SUBNET` in `.env` to a free subnet. Then run `just net-down` and
`just net-up`.

## A second lab

Change `LAB_NAME` and `LAB_SUBNET` in a second `.env` file. Every object gets
the new prefix, so the two labs do not conflict.
