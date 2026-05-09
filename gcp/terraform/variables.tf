variable "project_id" {
  description = "GCP project ID. Must exist with billing enabled. Set in terraform.tfvars (gitignored)."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (subnet, Cloud Router, Cloud NAT)."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for the zonal GKE cluster + node pools."
  type        = string
  default     = "europe-west1-b"
}

variable "project" {
  description = "Project name. Used as a prefix and label value for resources."
  type        = string
  default     = "merlins-lair"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the GKE control plane public endpoint (master authorized networks). Set in terraform.tfvars (gitignored)."
  type        = list(string)
}
