# The add-on cluster profile: what runs ON the cluster.
#
# A cluster carries one infrastructure profile and any number of add-on
# profiles. The difference is what a change costs:
#
#   infrastructure   os, k8s, cni, csi. A change rebuilds nodes.
#   add-on           workloads. A change is a Helm release on a live cluster.
#
# The dashboard is a workload, so it goes here. cluster-profile.tf stays the
# combination under test, and nothing in this file can make a node restart.
#
# To see the versions that the registry offers, and the values of one of them:
#
#   just palette-packs headlamp
#   just palette-packs headlamp 0.44.0

# ANCHOR: dashboardpack
# Headlamp is the Kubernetes web interface of the CNCF, and Palette ships it
# with a theme plugin of its own.
#
# It is NOT `spectro-k8s-dashboard`. That pack reads `system_state: disabled` in
# Public Repo, for every version from 2.7.0 to 7.14.0, and so does every version
# of `k8s-dashboard`. A disabled pack resolves, and it plans, and Palette then
# refuses the profile:
#
#   ClusterProfileInvalidPackState: Cluster Profile operation not supported as
#   pack spectro-k8s-dashboard:2.7.1 is disabled
#
# `just palette-packs <name>` prints that state in the last column. Read it
# before you pin any pack.
#
# The lookup takes no `cloud`. An add-on pack belongs to none: headlamp carries
# the cloud type "all", so `cloud = ["edge-native"]` finds nothing and the
# message names the pack and not the reason. The four infrastructure packs need
# that key, because a name such as cni-calico exists for several clouds.
#
# Do NOT reach for `spectrocloud_pack_simple` with `type = "helm"` here. It
# resolves, the plan is clean, and Palette then refuses the profile:
#
#   Invalid parameter 'PackType'; caused by: PackType 'helm' is not matching
#   with registry type 'pack' for pack ''
#
# Public Repo is a PACK registry, not a Helm registry. A pack that carries a
# Helm chart inside it is still a pack. `pack_simple` with `type = "helm"` is
# for a Helm registry that you added yourself.
data "spectrocloud_pack" "dashboard" {
  name         = "headlamp"
  version      = var.dashboard_version
  registry_uid = data.spectrocloud_registry.public.id
}
# ANCHOR_END: dashboardpack

# ANCHOR: dashboardvalues
# One line of the pack values, for the same reason as the pod range above it.
#
# The pack is built to be served BEHIND THE PALETTE CONSOLE. Its sign-in stores
# the token in a cookie, and it scopes that cookie to the console path of the
# tenant application:
#
#   Set-Cookie: headlamp-auth-main.0=...;
#     Path=/v1/tenantApps/<foreqID>/clusters/main; HttpOnly; Secure
#
# A port forward serves the same pod at "/". The path does not match, so the
# browser never sends the cookie back, every request after the sign-in carries
# no credential, and the page reports "error authenticating". The token is
# correct and the service account is correct; the cookie simply never returns.
# A bearer header still works, and a browser does not send one.
#
# `unsafeUseServiceAccountToken` makes Headlamp use the service account of its
# own pod, so it asks for no sign-in at all. Palette calls that UNSAFE, and the
# word is right: whoever reaches the service gets cluster-admin. It is sound
# HERE and only here, because the service is a ClusterIP that nothing outside
# the cluster can reach, and the one way in is `just dashboard`, which needs the
# administrator kubeconfig before it can forward the port. Give the service an
# ingress or a load balancer address and this value becomes wrong.
locals {
  dashboard_default_auth = "unsafeUseServiceAccountToken: false"
  dashboard_values = replace(
    data.spectrocloud_pack.dashboard.values,
    local.dashboard_default_auth,
    "unsafeUseServiceAccountToken: true",
  )
}
# ANCHOR_END: dashboardvalues

# ANCHOR: addonprofile
# The pack takes its default values with that one line replaced. The rest
# installs the headlamp chart into the namespace `headlamp`, with a ClusterIP
# service on port 443 and a service account bound to cluster-admin.
resource "spectrocloud_cluster_profile" "addon" {
  name        = "${var.cluster_name}-addon"
  description = "Add-on profile for ${var.cluster_name}: the Headlamp Kubernetes web interface"
  cloud       = "all"
  type        = "add-on"
  version     = "1.0.0"

  lifecycle {
    # A `replace` that matches nothing changes nothing, and it reports nothing.
    # Headlamp would then ask for a sign-in that cannot complete over a port
    # forward, and the page would name no cause. Fail here instead. This is the
    # same lesson as the pod range in cluster-profile.tf.
    precondition {
      condition = strcontains(
        data.spectrocloud_pack.dashboard.values,
        local.dashboard_default_auth
      )
      error_message = "headlamp ${var.dashboard_version} does not carry the default 'unsafeUseServiceAccountToken: false', so Headlamp keeps its sign-in page and that page cannot complete over a port forward. Read the values of this pack version and correct dashboard_default_auth in terraform/addon-profile.tf:  just palette-packs headlamp ${var.dashboard_version}"
    }
  }

  # No `type`. The default is "spectro", which is what a pack from a pack
  # registry is. See the data source above for the error that "helm" gives.
  pack {
    name         = data.spectrocloud_pack.dashboard.name
    tag          = var.dashboard_version
    uid          = data.spectrocloud_pack.dashboard.id
    registry_uid = data.spectrocloud_registry.public.id
    values       = local.dashboard_values
  }
}
# ANCHOR_END: addonprofile
