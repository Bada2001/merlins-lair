# Outputs are added as resources come online:
#   Day 2  — VPC + subnet (current)
#   Day 3  — GKE cluster name, endpoint, kubeconfig command, WI pool
#   Day 4  — Artifact Registry repo URL
#   Day 5  — Pub/Sub topic + subscription names
#   Day 6  — App pod GCP service account emails + WI bindings
#   Day 20 — Cloud Monitoring dashboard URL

# ── Day 2: VPC ───────────────────────────────────────────────────────────

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "vpc_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnet_name" {
  value = google_compute_subnetwork.nodes.name
}

output "subnet_secondary_ranges" {
  description = "Names of the secondary ranges (pods + services) on the subnet."
  value       = [for r in google_compute_subnetwork.nodes.secondary_ip_range : r.range_name]
}

output "cloud_nat_name" {
  value = google_compute_router_nat.nat.name
}
