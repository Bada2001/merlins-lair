provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "merlins-lair"
      ManagedBy = "terraform"
      Owner     = "vasco"
    }
  }
}
