# The credentials come from the environment. `scripts/cluster.sh` reads the API
# key from ~/.config/palette-edge-libvirt/api-key and exports it as
# SPECTROCLOUD_APIKEY, and it exports PALETTE_ENDPOINT as SPECTROCLOUD_HOST. The
# key is never a variable, so it never reaches the state file or a plan file.
provider "spectrocloud" {
  project_name = var.palette_project
}

# Stop at plan time if the project is absent or the API key cannot see it.
#
# A wrong project name is the failure that costs the most time in this
# repository: Palette reports nothing, and the objects simply go somewhere else.
# This data source turns that silence into an error before OpenTofu makes
# anything.
data "spectrocloud_project" "this" {
  name = var.palette_project
}
