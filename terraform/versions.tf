# The cluster layer. OpenTofu makes the cluster profile and the cluster, and
# both live in Palette. `scripts/cluster.sh` is the only caller. Run OpenTofu
# through `just cluster-up`, `just cluster-plan`, and `just cluster-down`, so
# the state path and the credentials are always the same.

terraform {
  # ANCHOR: pins
  required_version = ">= 1.9.0"

  required_providers {
    spectrocloud = {
      source  = "spectrocloud/spectrocloud"
      version = "0.29.9"
    }
  }
  # ANCHOR_END: pins

  # ANCHOR: backend
  # The state stays on the workstation, and it stays out of the checkout. The
  # path is empty here on purpose: a backend block takes no variable, so
  # `scripts/cluster.sh` gives the path at init time:
  #
  #   tofu init -backend-config=path=$PEL_STATE_DIR/<project>/terraform.tfstate
  #
  # One project gets one state file, so a second project builds its own cluster
  # and neither one can destroy the objects of the other. The same script also
  # sets TF_DATA_DIR, so the provider files stay out of the checkout too.
  backend "local" {}
  # ANCHOR_END: backend
}
