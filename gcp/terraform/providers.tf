provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  default_labels = {
    project    = "merlins-lair"
    managed-by = "terraform"
    owner      = "vasco"
  }
}
