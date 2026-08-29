# Architecture

## The parts

```mermaid
flowchart TB
    subgraph SaaS["Palette SaaS (api.spectrocloud.com)"]
        PROF["Cluster profile<br/>OS, CNI, CSI, add-ons"]
        HOSTS["Edge Hosts registry"]
        CLU["Edge Native cluster"]
    end

    subgraph WS["Workstation"]
        JUST["just recipes"]
        subgraph LV["libvirt / KVM"]
            NET["pe-net<br/>NAT 192.168.140.0/24"]
            POOL["pe-pool<br/>qcow2 disks"]
            CP["pe-cp-1"]
            WK1["pe-wk-1"]
            WK2["pe-wk-2"]
        end
        ISO["iso/<br/>installer ISO"]
        SEED["seeds/<br/>CIDATA per host"]
    end

    JUST --> NET
    JUST --> POOL
    JUST --> ISO
    JUST --> SEED
    ISO --> CP
    SEED --> CP
    CP --- NET
    WK1 --- NET
    WK2 --- NET
    CP -->|register| HOSTS
    WK1 -->|register| HOSTS
    WK2 -->|register| HOSTS
    HOSTS --> CLU
    PROF --> CLU
```

The workstation owns the virtual machines. Palette owns the cluster profile and
the cluster. The seed ISO is the only link between the two. It carries your
endpoint, your project, and your registration token.

## The lifecycle of one host

```mermaid
sequenceDiagram
    participant U as You
    participant J as just
    participant V as libvirt
    participant P as Palette

    U->>J: just cluster-up
    J->>J: preflight, infra-up, iso-fetch
    J->>J: seed-iso.sh makes the CIDATA ISO
    J->>V: virt-install (disk boot.order=1, ISO boot.order=2)
    V->>V: the disk is empty, so the firmware uses the ISO
    V->>V: the Edge installer writes the disk
    V->>P: the agent registers with the token
    P-->>U: the host shows at Clusters > Edge Hosts
    V->>V: reboot, the firmware now uses the disk
    U->>P: make an Edge Native cluster from the hosts
```

## Why the boot order matters

The system disk is `boot.order=1`. The installer ISO is `boot.order=2`. At the
first boot the disk is empty, so the firmware finds no boot loader and uses the
ISO. After the installation the disk has a boot loader, so the firmware uses the
disk. The result is one installation and no installation loop.

The alternative is an eject of the ISO at the correct moment. That is a manual
step, and a manual step breaks
[project rule 1](./rules.md#1-every-action-is-a-recipe).

This is the command that sets the order:

```bash
{{#include ../../scripts/host-up.sh:virtinstall}}
```

## Where the state lives

| State | Location | Removed by |
| --- | --- | --- |
| Virtual machines | libvirt, `qemu:///system` | `just cluster-down` |
| Disk images | `/var/lib/libvirt/images/$LAB_NAME` | `just cluster-down` |
| Network and pool | libvirt | `just infra-down` |
| Seed ISO files | `seeds/` (git ignores) | `just seed-clean` |
| Installer ISO | `iso/` (git ignores) | `just iso-clean` |
| Your token | `.env` (git ignores) | you delete the file |
| Edge Hosts, profiles, clusters | Palette SaaS | you, in Palette |

`just nuke` removes every local item except the installer ISO. Palette keeps the
Edge Host entries. Remove those entries in Palette.
