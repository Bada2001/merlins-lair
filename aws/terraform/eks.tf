locals {
  cluster_name = "${var.project}-eks"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.30"

  # Endpoint: in-cluster traffic stays on the VPC (private),
  # plus a public endpoint locked to my home IP for kubectl.
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.api_allowed_cidrs

  # v20 replaced the aws-auth ConfigMap with EKS Access Entries.
  # This grants the IAM principal running `terraform apply` cluster-admin.
  enable_cluster_creator_admin_permissions = true

  # POC: skip envelope encryption of K8s secrets to drop the $1/mo KMS key.
  create_kms_key            = false
  cluster_encryption_config = {}

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    system = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 1
      desired_size = 1
    }

    gpu = {
      instance_types = ["g4dn.xlarge"]
      capacity_type  = "SPOT"
      ami_type       = "AL2_x86_64_GPU"

      min_size     = 0
      max_size     = 3
      desired_size = 0

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "present"
          effect = "NO_SCHEDULE"
        }
      }

      labels = {
        "nvidia.com/gpu" = "true"
      }
    }
  }
}
