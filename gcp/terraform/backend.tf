terraform {
  # GCS backend handles state locking natively via object generation numbers
  # — no separate lock table needed (unlike S3 + DynamoDB on the AWS side).
  # The bucket must exist before `terraform init`. Create it manually with
  # versioning enabled (Day 1 in 01-plan.md).
  backend "gcs" {
    bucket = "merlin-terraform-state"
    prefix = "gke/terraform.tfstate"
  }
}
