# The cluster. Palette builds it on the hosts that layer 1 registered.
#
# The two layers meet here. `just infra-up` does not return until every host is
# ready in Palette, so every name below already has a record when OpenTofu
# reads it.

# ANCHOR: appliances
# One lookup for each host. The lookup is the test: a name that never registered
# stops the plan with that name in the message, instead of building a cluster
# that waits forever for a host that does not exist.
#
# For an agent-mode host the uid and the name are the same value, because the
# seed ISO gives `stylus.site.name` the libvirt domain name. The lookup stays
# because it proves the record is there, and because a uid that Palette chooses
# for itself would still be correct here.
data "spectrocloud_appliance" "control_plane" {
  for_each = toset(var.control_plane_hosts)
  name     = each.value
}

data "spectrocloud_appliance" "worker" {
  for_each = toset(var.worker_hosts)
  name     = each.value
}
# ANCHOR_END: appliances

# ANCHOR: cluster
resource "spectrocloud_cluster_edge_native" "this" {
  name        = var.cluster_name
  description = "Edge Native cluster on the libvirt machines of ${var.cluster_name}"

  cloud_config {
    # The control plane endpoint. Palette answers "Parameter 'Host endpoint'
    # should not be empty" without it, for one control plane node as well as
    # for three, so this address is never empty. kube-vip on the hosts claims
    # it, which is why the seed ISO sets PALETTE_VIP_SKIP=false.
    #
    # Use a free address of the cluster subnet, below the DHCP pool. See
    # docs/src/network.md for the address plan.
    vip = var.vip
  }

  # The infrastructure profile builds the nodes. It comes first, and a cluster
  # has exactly one.
  cluster_profile {
    id = spectrocloud_cluster_profile.infra.id
  }

  # The add-on profile runs on the nodes that the profile above built. Palette
  # installs it after the cluster answers, so it costs no node restart. See
  # terraform/addon-profile.tf.
  #
  # The `pack` block repeats what the profile holds, and it has to.
  #
  # PALETTE GIVES A CLUSTER ITS OWN COPY OF A PROFILE, taken when the profile is
  # attached. An edit to the profile after that changes the profile and nothing
  # else: the console shows the new value, the cluster keeps the old one, and no
  # pod restarts. Only the cluster carries the values that run.
  #
  # With `id` alone this resource has nothing to compare, so OpenTofu reports no
  # change to make and the two copies drift apart for ever. The values here are
  # the same `local.dashboard_values`, so a change to them is a change to this
  # resource, and the provider writes it to the cluster.
  cluster_profile {
    id = spectrocloud_cluster_profile.addon.id

    pack {
      name   = data.spectrocloud_pack.dashboard.name
      tag    = var.dashboard_version
      uid    = data.spectrocloud_pack.dashboard.id
      values = local.dashboard_values
    }
  }

  # How a service of the cluster reaches the outside. LoadBalancer is the choice
  # that needs nothing else: Ingress needs an ingress controller, and this
  # profile holds none.
  #
  # This block does not answer "Parameter 'Host endpoint' should not be empty".
  # That message is about the control plane endpoint, which is `vip` above.
  host_config {
    host_endpoint_type = "LoadBalancer"
  }

  machine_pool {
    name          = "control-plane-pool"
    control_plane = true

    # A single control plane node also carries the workload. Without this,
    # Palette taints the node and a one-node cluster schedules nothing.
    control_plane_as_worker = length(var.control_plane_hosts) == 1

    dynamic "edge_host" {
      for_each = data.spectrocloud_appliance.control_plane
      content {
        host_uid  = edge_host.value.id
        host_name = edge_host.value.name
      }
    }
  }

  # The pool exists only when the topology has workers. A cluster of one control
  # plane node and no worker is a correct cluster, and an empty pool is not:
  # the provider needs at least one host in each pool it is given.
  dynamic "machine_pool" {
    for_each = length(var.worker_hosts) > 0 ? [1] : []
    content {
      name = "worker-pool"

      dynamic "edge_host" {
        for_each = data.spectrocloud_appliance.worker
        content {
          host_uid  = edge_host.value.id
          host_name = edge_host.value.name
        }
      }
    }
  }

  # Palette installs four packs on every node. The default of 60 minutes is
  # short for a workstation that runs each node as a virtual machine.
  timeouts {
    create = "90m"
    update = "90m"
    delete = "30m"
  }
}
# ANCHOR_END: cluster
