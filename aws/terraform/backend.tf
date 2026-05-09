terraform {
  backend "s3" {
    bucket       = "merlins-lair-tfstate-949160680805"
    key          = "eks/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    encrypt      = true
  }
}