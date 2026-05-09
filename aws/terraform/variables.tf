variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name. Used as a prefix and tag value for resources."
  type        = string
  default     = "merlins-lair"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint. Set in terraform.tfvars (gitignored)."
  type        = list(string)
}
