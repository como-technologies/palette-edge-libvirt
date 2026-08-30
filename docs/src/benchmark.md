# Benchmark

This page gives the time of each step of the [Introduction](./introduction.md),
forward and then in reverse.

The measurement ran three times on 2026-08-30, against the live Palette tenant.

## The result

| Step | Direction | run 1 | run 2 | run 3 | Mean |
| --- | --- | ---: | ---: | ---: | ---: |
| `tofu-install` | forward | 0.0s | 2.1s | 1.9s | 1.3s |
| `api-key-set` | forward | 0.0s | 0.0s | 0.0s | 0.0s |
| `new-project` | forward | 2.3s | 2.9s | 2.7s | 2.6s |
| `infra-up` | forward | 209.1s | 179.1s | 186.5s | **191.6s** |
| `cluster-up` | forward | 636.3s | 667.9s | 633.9s | **646.0s** |
| `cluster-kubeconfig` | forward | 0.4s | 2.7s | 0.4s | 1.2s |
| `cluster-down` | reverse | 39.6s | 46.0s | 39.7s | **41.8s** |
| `infra-down` | reverse | 9.6s | 7.0s | 8.9s | 8.5s |
| `remove-project` | reverse | 4.1s | 3.5s | 3.3s | 3.6s |
| `image-clean` | reverse | 0.1s | 0.1s | 0.1s | 0.1s |
| `api-key-clear` | reverse | 0.0s | 0.0s | 0.0s | 0.0s |
| `tofu-uninstall` | reverse | 0.0s | 0.0s | 0.0s | 0.0s |
| **Round trip** | | 901.5s | 911.3s | 877.4s | **896.7s** |

All 36 steps returned 0.

| Direction | Mean |
| --- | ---: |
| Forward, `tofu-install` to `cluster-kubeconfig` | 842.7s (14 minutes) |
| Reverse, `cluster-down` to `tofu-uninstall` | 54.0s |

In run 1, `tofu-install` found OpenTofu installed and made no change. Runs 2 and
3 downloaded it and installed it.

## Where the time goes

Two steps take 93 percent of the round trip. Each one is a wait.

- `cluster-up` is 72 percent. Palette installs four packs on three nodes.
- `infra-up` is 21 percent. Each host starts, cloud-init installs the agent, the
  host starts again one time, and the agent registers.

The other ten steps take 59 seconds together.

A build of both layers takes 14 minutes. A removal of both layers takes 50
seconds. To make both layers again, count 15 minutes.

## The cloud image

In run 1, the cache held the cloud image. In runs 2 and 3, `image-clean` had
removed it, and `infra-up` downloaded the 624 MB image again.

Runs 2 and 3 were faster than run 1. The difference between the three times of
`infra-up` is larger than the time of the download.

## The workstation

| Part | Value |
| --- | --- |
| Model | System76 Thelio |
| CPU | AMD Ryzen 9 7950X, 16 cores, 32 threads, 5.88 GHz maximum |
| Memory | 124 GB |
| Disk | Crucial T700 NVMe, 931 GB, 791 GB free |
| Operating system | Ubuntu 24.04.4 LTS, kernel 7.0.11-76070011-generic |
| Network | Wi-Fi 6, 5 GHz, 720 Mbit/s link, 36 MB/s measured download |

| Tool | Version |
| --- | --- |
| libvirt | 10.0.0 |
| QEMU | 8.2.2 |
| virt-install | 4.1.0 |
| genisoimage | 1.1.11 |
| OpenTofu | 1.12.6 |
| `spectrocloud` provider | 0.29.9 |

## The configuration

The default topology, which `just new-project` writes:

| Setting | Value |
| --- | --- |
| `CONTROL_COUNT` | 1 x 4 vcpu / 8192 MB / 100 GB |
| `WORKER_COUNT` | 2 x 6 vcpu / 16384 MB / 100 GB |
| `POD_CIDR` | 10.244.0.0/16 |
| `UBUNTU_RELEASE` | noble |

The topology needs 16 vcpu and 40 GB. See
[The workstation](./workstation.md).

The pinned packs:

| Pack | Version |
| --- | --- |
| `edge-native-byoi` (Agent Mode) | 2.1.0 |
| `edge-k8s` (PXK-E) | 1.33.13 |
| `cni-calico` | 3.32.1 |
| `csi-local-path-provisioner` | 0.0.37 |

## The method

Each step is one recipe, so a measurement is the two tables of the
[Introduction](./introduction.md) with a clock:

```bash
for step in tofu-install "new-project bench" infra-up cluster-up; do
    start=$(date +%s)
    just $step
    printf '%-20s %ss\n' "$step" "$(( $(date +%s) - start ))"
done
```

Two steps of the tables did not run. `host-setup` and `host-setup-undo` install
and remove libvirt and KVM, and they need a restart of the workstation.

`just new-project` gives each project a free `CLUSTER_NAME`. A new name needs
the root password one time, to make the pool directory of the cluster. The three
runs therefore used one name.
