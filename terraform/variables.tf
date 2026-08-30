# Every variable takes its value from the project environment file, through
# `scripts/cluster.sh`. The script exports each one as TF_VAR_<name>, so
# `just config` and OpenTofu always agree. Nothing here holds a secret.

variable "palette_project" {
  description = "Palette project that owns the cluster profile and the cluster. PALETTE_PROJECT in the project environment file."
  type        = string

  validation {
    condition     = length(var.palette_project) > 0
    error_message = "palette_project is empty. Run: just default-project <name>"
  }
}

variable "cluster_name" {
  description = "Name of the cluster in Palette, and the prefix of the cluster profile. CLUSTER_NAME in the project environment file, so the Palette cluster and the libvirt domains carry the same name."
  type        = string
}

# ANCHOR: hosts
variable "control_plane_hosts" {
  description = "Edge host names for the control plane pool. The tooling gives the libvirt domain and the Palette host the same name, so these are the <cluster>-cp-N names that `just ls` prints."
  type        = list(string)

  validation {
    condition     = length(var.control_plane_hosts) % 2 == 1
    error_message = "A Kubernetes control plane needs an odd number of nodes for etcd quorum. Set CONTROL_COUNT to 1, 3, or 5."
  }
}

variable "worker_hosts" {
  description = "Edge host names for the worker pool"
  type        = list(string)
}
# ANCHOR_END: hosts

# ANCHOR: vip
variable "vip" {
  description = "Virtual address of the control plane, from the free range of the cluster subnet. Palette refuses a cluster that gives no control plane endpoint, so this value is never empty. kube-vip claims the address, and the seed ISO enables kube-vip with PALETTE_VIP_SKIP=false."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.vip))
    error_message = "vip must be an IPv4 address of the cluster subnet, outside the DHCP pool. Set CLUSTER_VIP in the project environment file."
  }
}
# ANCHOR_END: vip

# ANCHOR: podcidr
variable "pod_cidr" {
  description = "Address range for the pods. It must not hold CLUSTER_SUBNET, and it must not hold the address of your workstation. The pack default 192.168.0.0/16 holds both, so this value replaces it."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a CIDR range, for example 10.244.0.0/16. Set POD_CIDR in the project environment file."
  }
}
# ANCHOR_END: podcidr

# ANCHOR: packversions
variable "os_pack_version" {
  description = "Version of the BYOOS pack. The Agent Mode preset of this pack is what makes the profile match a host that runs the Palette agent on a stock Ubuntu image."
  type        = string
  default     = "2.1.0"
}

variable "k8s_version" {
  description = "Version of the edge-k8s pack, which is Palette eXtended Kubernetes - Edge (PXK-E)"
  type        = string
  default     = "1.33.13"
}

variable "cni_version" {
  description = "Version of the cni-calico pack. Palette lists Ubuntu with PXK-E and Calico as a verified combination."
  type        = string
  default     = "3.32.1"
}

variable "csi_version" {
  description = "Version of the csi-local-path-provisioner pack. Edge needs no CSI, but a cluster with no storage class runs nothing that keeps data."
  type        = string
  default     = "0.0.37"
}
# ANCHOR_END: packversions

variable "console_url" {
  description = "Base URL of the Palette console, for the link that `just cluster-show` prints"
  type        = string
  default     = "https://console.spectrocloud.com"
}
