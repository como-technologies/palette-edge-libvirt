# The infrastructure cluster profile: the combination under test.
#
# Four layers, all from the Palette public registry, and every version pinned:
#
#   os    edge-native-byoi              BYOOS, Agent Mode preset
#   k8s   edge-k8s                      Palette eXtended Kubernetes - Edge
#   cni   cni-calico                    verified with Ubuntu and PXK-E
#   csi   csi-local-path-provisioner    a storage class that needs no hardware
#
# To find the versions that a pack offers now:  just palette-packs <name>

# ANCHOR: registry
# The Palette public pack registry. Every pack below comes from it, so the
# profile needs no registry of your own and no pack to push.
data "spectrocloud_registry" "public" {
  name = "Public Repo"
}
# ANCHOR_END: registry

# ANCHOR: packs
# `cloud` keeps each lookup inside the Edge Native packs. Names such as
# cni-calico exist for several infrastructure providers, and a pack for the
# wrong provider is rejected only when Palette builds the profile.
data "spectrocloud_pack" "os" {
  name         = "edge-native-byoi"
  version      = var.os_pack_version
  cloud        = ["edge-native"]
  registry_uid = data.spectrocloud_registry.public.id
}

data "spectrocloud_pack" "k8s" {
  name         = "edge-k8s"
  version      = var.k8s_version
  cloud        = ["edge-native"]
  registry_uid = data.spectrocloud_registry.public.id
}

data "spectrocloud_pack" "cni" {
  name         = "cni-calico"
  version      = var.cni_version
  cloud        = ["edge-native"]
  registry_uid = data.spectrocloud_registry.public.id
}

data "spectrocloud_pack" "csi" {
  name         = "csi-local-path-provisioner"
  version      = var.csi_version
  cloud        = ["edge-native"]
  registry_uid = data.spectrocloud_registry.public.id
}
# ANCHOR_END: packs

# ANCHOR: podcidr
# The pack default for the pod range.
#
# 192.168.0.0/16 holds every subnet that `just new-project` allocates
# (192.168.140 to 192.168.199), and it holds most home and office networks as
# well. Calico gives no NAT to a destination inside its own pool, so a pod that
# asks the gateway of the cluster network for DNS gets no answer, and the whole
# cluster then waits for a name that it cannot resolve.
#
# The correction is one line of the pack values. `replace` keeps every other
# default, so a new pack version needs no new copy of 391 lines.
locals {
  k8s_default_pod_cidr = "192.168.0.0/16"
  k8s_values = replace(
    data.spectrocloud_pack.k8s.values,
    "podSubnet: ${local.k8s_default_pod_cidr}",
    "podSubnet: ${var.pod_cidr}",
  )
}
# ANCHOR_END: podcidr

# ANCHOR: profile
resource "spectrocloud_cluster_profile" "infra" {
  name        = "${var.cluster_name}-infra"
  description = "Infrastructure profile for agent-mode Edge hosts: BYOOS, PXK-E ${var.k8s_version}, Calico, local-path storage"
  cloud       = "edge-native"
  type        = "cluster"
  version     = "1.0.0"

  lifecycle {
    # The values in values/edge-native-byoi.yaml belong to the pack version
    # that its header names. A re-pin without a re-vendor must fail here, and
    # not on a cluster that is already building.
    precondition {
      condition = strcontains(
        file("${path.module}/values/edge-native-byoi.yaml"),
        "pack `edge-native-byoi` ${var.os_pack_version}"
      )
      error_message = "terraform/values/edge-native-byoi.yaml was not vendored from the pinned edge-native-byoi version. Read the default values of the new version, apply the two marked changes again, and correct the version in the header."
    }

    # A `replace` that matches nothing changes nothing, and it reports nothing.
    # The pod range would then keep the pack default, and the cluster would fail
    # much later on a name that it cannot resolve. Fail here instead.
    precondition {
      condition = strcontains(
        data.spectrocloud_pack.k8s.values,
        "podSubnet: ${local.k8s_default_pod_cidr}"
      )
      error_message = "edge-k8s ${var.k8s_version} does not carry the default 'podSubnet: 192.168.0.0/16', so the pod range was not replaced. Read the values of this pack version and correct k8s_default_pod_cidr in terraform/cluster-profile.tf."
    }
  }

  # The operating system layer. The values select the Agent Mode preset, which
  # is what makes this profile match a host that runs the Palette agent on the
  # stock Ubuntu cloud image. Read the file for the reason for each change.
  pack {
    name   = data.spectrocloud_pack.os.name
    tag    = var.os_pack_version
    uid    = data.spectrocloud_pack.os.id
    values = file("${path.module}/values/edge-native-byoi.yaml")
  }

  # The Kubernetes layer takes the default values with one line replaced: the
  # pod range. See the locals block above for the reason.
  pack {
    name   = data.spectrocloud_pack.k8s.name
    tag    = var.k8s_version
    uid    = data.spectrocloud_pack.k8s.id
    values = local.k8s_values
  }

  # The last two layers take the default values of the pack. Nothing in this
  # repository needs a change there, and a default that Palette updates is
  # better than a copy that goes stale.

  pack {
    name   = data.spectrocloud_pack.cni.name
    tag    = var.cni_version
    uid    = data.spectrocloud_pack.cni.id
    values = data.spectrocloud_pack.cni.values
  }

  pack {
    name   = data.spectrocloud_pack.csi.name
    tag    = var.csi_version
    uid    = data.spectrocloud_pack.csi.id
    values = data.spectrocloud_pack.csi.values
  }
}
# ANCHOR_END: profile
