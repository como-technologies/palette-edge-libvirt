# `just cluster-show` prints these. The kubeconfig is separate, because it is a
# credential: `just cluster-kubeconfig` prints it, and nothing else does.

output "cluster_profile_id" {
  description = "Palette uid of the infrastructure cluster profile"
  value       = spectrocloud_cluster_profile.infra.id
}

output "cluster_id" {
  description = "Palette uid of the cluster"
  value       = spectrocloud_cluster_edge_native.this.id
}

output "control_plane_hosts" {
  description = "Edge hosts in the control plane pool"
  value       = var.control_plane_hosts
}

output "worker_hosts" {
  description = "Edge hosts in the worker pool"
  value       = var.worker_hosts
}

output "console_url" {
  description = "The page for this cluster in the Palette console"
  value = format(
    "%s/projects/%s/clusters/%s/overview",
    var.console_url,
    data.spectrocloud_project.this.id,
    spectrocloud_cluster_edge_native.this.id,
  )
}

# ANCHOR: kubeconfig
# The administrator kubeconfig. It carries a client certificate, so OpenTofu
# holds it back from every listing. `just cluster-kubeconfig` asks for this one
# output by name and prints nothing else.
output "kubeconfig" {
  description = "Administrator kubeconfig of the cluster"
  value       = spectrocloud_cluster_edge_native.this.admin_kube_config
  sensitive   = true
}
# ANCHOR_END: kubeconfig
