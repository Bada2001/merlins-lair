# Outputs are added as resources come online:
#   Day 2  — VPC id, subnet ids
#   Day 3  — EKS cluster name, endpoint, kubeconfig command
#   Day 4  — ECR repo URL, SQS queue URLs
#   Day 5  — App pod IRSA role ARN
#   Day 20 — CloudWatch dashboard URL

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
