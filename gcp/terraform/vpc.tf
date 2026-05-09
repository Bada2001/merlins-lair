locals {
  # Primary range — node internal IPs.
  subnet_cidr_nodes = "10.10.0.0/20" # 4,096 addresses

  # Secondary range — pod IPs (alias IPs). GKE allocates a /24 per node by default,
  # so /14 = ~1,024 nodes worth of pod IPs. Massive overkill, but free.
  subnet_cidr_pods = "10.16.0.0/14" # ~262k addresses

  # Secondary range — service ClusterIPs.
  subnet_cidr_services = "10.20.0.0/20" # 4,096 services

  # Private GKE control plane endpoint range. Must be a /28, must not overlap
  # with anything else in the VPC. GKE peers this range into our VPC automatically.
  master_cidr = "172.16.0.0/28"
}

# A custom-mode VPC. Auto-mode would create a subnet per region with default CIDRs;
# custom mode means we own the address plan.
resource "google_compute_network" "vpc" {
  name                    = "${var.project}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Single subnet in our region. GKE nodes get IPs from the primary range; pods + services
# get IPs from the secondary ranges via VPC-native (alias IPs).
resource "google_compute_subnetwork" "nodes" {
  name          = "${var.project}-nodes"
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = local.subnet_cidr_nodes

  # Lets nodes reach Google APIs (Artifact Registry, GCS, logging) over Google's
  # internal network instead of going out via Cloud NAT — faster and free.
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = local.subnet_cidr_pods
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = local.subnet_cidr_services
  }
}

# Cloud Router is the control plane that hosts Cloud NAT (and BGP for VPN/Interconnect,
# which we don't use). One router, one NAT — both regional.
resource "google_compute_router" "router" {
  name    = "${var.project}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT gives private nodes outbound internet for things Google's private access
# can't cover (e.g. NGC image pulls from nvcr.io, pip installs from pypi.org).
# Single regional NAT — no per-zone redundancy needed at POC scale.
resource "google_compute_router_nat" "nat" {
  name                               = "${var.project}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}
