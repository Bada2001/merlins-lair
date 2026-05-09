# merlins-lair

Personal POC: deploy NVIDIA Merlin (recommender system inference) on Kubernetes with KEDA autoscaling, all infrastructure managed by Terraform.

The repo carries **two parallel stacks** — same target architecture, different cloud:

```
aws/   # Legacy/reference. Days 1-3 of the AWS plan: VPC + EKS + Makefile.
       # Pivoted away on May 7 2026; preserved unchanged for comparison.
gcp/   # Active stack. Same plan re-implemented on GCP — GKE, Cloud NAT,
       # Workload Identity, Pub/Sub. This is what's being built through end of May.
```

Each stack has the same internal layout:

```
<stack>/
  terraform/   # Infrastructure (VPC, cluster, registry, queues, IAM)
  k8s/         # Application K8s manifests (FastAPI, worker, ScaledObject)
  docker/      # Dockerfiles for FastAPI and Triton+Merlin worker images
  docs/        # Plan + day-by-day learning docs
  Makefile     # up / down / plan / apply / kubeconfig ritual
```

## Where to start

- **Active work:** [`gcp/docs/01-plan.md`](gcp/docs/01-plan.md) — current day-by-day plan, GCP version
- **Why the pivot:** see the "Why this plan replaces the AWS one" section in the GCP plan
- **AWS reference:** [`aws/docs/eks-merlin-project-plan-may-2026.md`](aws/docs/eks-merlin-project-plan-may-2026.md) — original plan, with `aws/docs/02-vpc.md` and `03-eks.md` walkthroughs

## Conventions

Stack-specific (region, tag/label keys, state backend) live in each stack's docs. Cross-stack:

- **Terraform:** `>= 1.6`. Provider versions pinned per stack.
- **One IaC dir per stack** with its own remote state — they share nothing.
- **No `terraform.tfvars` committed** (gitignored everywhere); each stack ships a `terraform.tfvars.example`.
- **Daily teardown ritual** via `make down` to keep cost meter sane.
