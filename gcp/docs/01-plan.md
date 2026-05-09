# GKE Merlin Inference Project — May 2026 (GCP refactor)

## Background
I'm an infrastructure engineer with 3 years of AWS serverless experience pivoting toward AI infrastructure. I'm building a personal POC over the month of May 2026 to demonstrate I can deploy GPU-based ML inference on Kubernetes with autoscaling. Working ~3 hours/day, 7 days a week. Budget: ~$130-160 for GCP for the rest of the month.

**Why this plan replaces the AWS one.** Days 1-3 of the AWS version delivered EKS + VPC + Makefile and are preserved under `aws/` as legacy/reference. Pivoted to GCP on May 7 because:

1. Many ML infra shops run on GCP (TPU access, Vertex AI ecosystem) — porting the same project surfaces the cloud-agnostic concepts vs the AWS-specific accidents.
2. Workload Identity is a meaningfully cleaner abstraction than IRSA — rebuilding on it is the fastest way to internalize the difference.
3. GCP free credits ($300/90d) come with no instance-type restrictions, unlike the AWS Free Plan trap that ate Day 3.
4. GKE Autopilot exists as an option for later experimentation; AWS has no equivalent.

The K8s-internal layer (KEDA, Triton, Merlin, Helm, the worker script) ports unchanged — the rewrite is the IaC + queue layer.

## Goal
Deploy NVIDIA Merlin (recommender system inference) on GKE with KEDA autoscaling, all infrastructure managed by Terraform. Same end state as the AWS plan, on a different cloud.

## Architecture
- Client → FastAPI (Service `type: LoadBalancer`) → Pub/Sub topic `inference-requests` → KEDA-scaled worker pods → Triton Inference Server with Merlin DLRM model on GPU → Pub/Sub topic `inference-responses`
- GKE Cluster Autoscaler manages the GPU node pool (scale to zero when idle)
- Cloud Monitoring dashboards + alerting + Cloud Logging (auto-collected from stdout/stderr)
- Everything in Terraform except: Docker builds, app K8s manifests during dev, kubectl debugging
- `terraform destroy` cleans up everything at the end

## Stack
- GKE Standard, zonal cluster, Kubernetes 1.30 release channel REGULAR
- Node pools: e2-medium x1 system (on-demand), n1-standard-4 + nvidia-tesla-t4 GPU (Spot, min 0 max 3)
- Triton Inference Server with Merlin DLRM example (pre-trained on Criteo)
- Base image: `nvcr.io/nvidia/merlin/merlin-tensorflow:latest`
- KEDA for Pub/Sub-triggered autoscaling
- FastAPI for ingestion, Python worker for Pub/Sub pull
- Terraform raw resources (`google_container_cluster`, `google_compute_*`) — no community module wrapper, for clarity
- Remote state in GCS (object generation handles locking; no DynamoDB equivalent needed)

## Simplifications (deliberate, for POC scope)
- Pre-trained model only, no training pipeline
- Single Triton model, no ensembles
- No NVTabular preprocessing pipeline, no feature store
- Pre-computed Criteo features as input
- Zonal cluster (no control-plane HA), single Cloud NAT (no multi-region)
- These are documented in README as "production maturity roadmap"

## Service mapping vs AWS plan

| Concern | AWS (legacy) | GCP (active) |
|---|---|---|
| K8s control plane | EKS | GKE Standard zonal |
| VPC | terraform-aws-modules/vpc, 3 AZs | Custom-mode VPC, 1 region, alias IPs (secondary ranges) |
| Egress | NAT Gateway (1) | Cloud NAT (1) |
| API allowlist | `cluster_endpoint_public_access_cidrs` | `master_authorized_networks_config` |
| Cluster admin | EKS Access Entries | GCP IAM `roles/container.admin` + K8s RBAC |
| Container registry | ECR | Artifact Registry |
| Queue | SQS (FIFO not needed) | Pub/Sub topic + pull subscription (push optional) |
| Pod-to-cloud auth | IRSA (OIDC + IAM role + pod annotation) | Workload Identity (K8s SA ↔ GCP SA binding) |
| GPU drivers | NVIDIA device plugin via Helm | GKE auto-install (`gpu_driver_installation_config { gpu_driver_version = "DEFAULT" }`) |
| Logs | Fluent Bit DaemonSet + CloudWatch | GKE managed Cloud Logging agent (auto, no install) |
| Metrics + dashboards | CloudWatch dashboards | Cloud Monitoring dashboards |
| Alarms | CloudWatch alarm + SNS | Cloud Monitoring alert policy + Notification Channel |
| Remote state | S3 + DynamoDB lock table | GCS bucket (locking via object generations) |
| Cost tagging | `default_tags` on aws provider | `default_labels` on google provider |

---

## Day-by-Day Plan (25 days, May 7 Wed → May 31 Sat)

### Week 1 — Foundation + GKE

**Day 1 · May 7 Wed · Project scaffold**
- Install: gcloud, kubectl (already installed for AWS — same binary), helm, docker (already installed)
- GCP project + billing enabled. Set $150 budget alert in Cloud Billing immediately
- Authenticate: `gcloud auth login` + `gcloud auth application-default login` (the second one is what Terraform uses)
- Manually create GCS bucket for Terraform state (versioning ON, location europe-west1) — only manual GCP step
- Scaffold: `versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`. Run `terraform init`
- Confirm `gcloud config list` shows the right project

**Day 2 · May 8 Thu · VPC**
- `vpc.tf`: custom-mode VPC, single subnet in `europe-west1` with secondary ranges for pods + services (alias IPs)
- Cloud Router + Cloud NAT (`AUTO_ONLY` external IPs, all subnets) for outbound from private nodes
- `private_ip_google_access = true` on the subnet — bypasses Cloud NAT for Google APIs (Artifact Registry, GCS, logging)
- Why no NAT-per-AZ like AWS: GCP Cloud NAT is regional + HA by design; you don't get to (or need to) deploy one per zone
- terraform apply, verify, commit
- Read `02-vpc.md` end-to-end and run the verification commands

**Day 3 · May 9 Fri · GKE cluster + node pools**
- `gke.tf` raw resources (no community module): `google_container_cluster` zonal, `remove_default_node_pool = true`
- Private nodes (`enable_private_nodes = true`), public+allowlisted control plane endpoint via `master_authorized_networks_config`
- Workload Identity on at cluster level (`workload_identity_config.workload_pool = "<project>.svc.id.goog"`)
- System node pool: e2-medium x1 (no autoscaling) — replaces t3.medium
- GPU node pool: n1-standard-4 + T4 SPOT, min:0 max:3 desired:0, taint `nvidia.com/gpu=present:NoSchedule`, GKE auto-installs NVIDIA drivers
- terraform apply (~10min — faster than EKS). `gcloud container clusters get-credentials`. `kubectl get nodes`
- Read `03-gke.md` end-to-end

**Day 4 · May 10 Sat · Week 1 buffer**
- Verify GPU node can come up: `kubectl scale deployment <test-gpu-pod>` or set min_node_count=1 temporarily
- `kubectl exec -- nvidia-smi` smoke test on a GPU node
- Cost check: GCP billing console
- Commit. terraform plan = no changes

---

### Week 2 — App infra + Workload Identity

**Day 5 · May 11 Sun · Artifact Registry + Pub/Sub**
- `artifact_registry.tf`: `google_artifact_registry_repository` for docker images, location `europe-west1`
- `pubsub.tf`: topic `inference-requests`, pull subscription with ack deadline 120s, message retention 1hr
- topic `inference-responses` + pull subscription
- Dead-letter topics + subscriptions for both
- Note: Pub/Sub has no "visibility timeout" exactly — equivalent is `ackDeadlineSeconds` on the subscription. Different model from SQS but same effect for our pull pattern.
- terraform apply, note topic + subscription names in outputs

**Day 6 · May 12 Mon · Workload Identity for app pods**
- `iam.tf`: `google_service_account` for the app workload (one for FastAPI, one for worker)
- `google_project_iam_member` granting `roles/pubsub.publisher` (FastAPI) and `roles/pubsub.subscriber` (worker)
- `google_service_account_iam_member` binding: K8s SA → GCP SA via `roles/iam.workloadIdentityUser`
- This is the single move that replaces all of AWS's IRSA OIDC plumbing
- Output the GCP SA emails — the K8s manifests will annotate K8s SAs with `iam.gke.io/gcp-service-account=<email>`
- Compare your understanding to `aws/docs/03-eks.md`'s OIDC issuer section to internalize the difference

**Day 7 · May 13 Tue · GPU stack verification**
- Verify NVIDIA drivers were auto-installed: `kubectl describe node <gpu-node> | grep nvidia.com/gpu` should show capacity 1
- GKE Cluster Autoscaler is built into the control plane — no Helm install needed (vs AWS where you Helm-install it)
- Smoke test: deploy a CUDA sample pod with `nvidia.com/gpu: 1` request + matching toleration, watch the GPU node spin up from 0
- Scale back to 0 when verified

**Day 8 · May 14 Wed · FastAPI app**
- FastAPI: `POST /recommend` accepts feature vector (Criteo schema), publishes to Pub/Sub `inference-requests`, returns request_id (the message_id from publish response)
- `GET /result/{request_id}` pulls from `inference-responses` and matches by attribute
- Dockerfile: `python:3.11-slim` base
- `docker build` + push to Artifact Registry (`gcloud auth configure-docker europe-west1-docker.pkg.dev` first)

**Day 9 · May 15 Thu · FastAPI on GKE**
- `k8s/fastapi-deployment.yaml`: Service `type: LoadBalancer`, K8s SA annotated with `iam.gke.io/gcp-service-account`
- Inject project_id + topic names as env vars (no SQS URL equivalent — Pub/Sub uses project + topic name)
- kubectl apply
- curl LoadBalancer external IP, verify message in Pub/Sub via `gcloud pubsub subscriptions pull`

**Day 10 · May 16 Fri · Get Merlin example model**
- `docker login nvcr.io` with NGC API key (same as AWS plan)
- Clone NVIDIA-Merlin/Merlin examples repo from GitHub
- Pick simplest pre-trained example: DLRM on Criteo (Triton-ready model files)
- Test the example locally with `docker compose` first if possible

**Day 11 · May 17 Sat · Build Triton+Merlin image**
- Dockerfile: `FROM nvcr.io/nvidia/merlin/merlin-tensorflow:latest`
- COPY model files into `/models` with `config.pbtxt` (single model, no ensemble)
- COPY `worker.py` for Pub/Sub pull loop
- docker build (~20GB), push to Artifact Registry — start early

---

### Week 3 — Worker + KEDA

**Day 12 · May 18 Sun · Worker script**
- `worker.py`: pull from Pub/Sub `inference-requests` → call Triton HTTP `/v2/models/dlrm/infer` → publish result to `inference-responses` → ack message
- Triton uses KFServing v2 protocol — request body has `inputs` array with name/shape/datatype/data
- Ack the Pub/Sub message only after successful inference + response publish
- Structured JSON logging to stdout — Cloud Logging picks it up automatically (no Fluent Bit needed)

**Day 13 · May 19 Mon · Worker on GKE + e2e test**
- `k8s/worker-deployment.yaml`: 0 replicas, GPU request, GPU toleration, K8s SA annotated for WI
- kubectl apply, scale to 1, verify GPU: `kubectl exec -- nvidia-smi`
- Full flow test: POST /recommend → Pub/Sub → Triton infer → response. Expect <100ms inference
- Scale worker back to 0 after testing

**Day 14 · May 20 Tue · KEDA install + ScaledObject**
- helm_release for KEDA, namespace=keda
- `google_service_account` for the KEDA operator (perms: `roles/pubsub.viewer`, `roles/monitoring.viewer`)
- WI binding for KEDA's K8s SA → GCP SA
- `k8s/scaledobject.yaml`: trigger `gcp-pubsub`, with `subscriptionName`, `mode: SubscriptionSize`
- minReplicaCount:0, maxReplicaCount:3, threshold:50
- scaleTargetRef → worker Deployment
- kubectl apply, kubectl get scaledobject (READY=True)

**Day 15 · May 21 Wed · Scale-out + scale-to-zero tests**
- Confirm worker at 0 replicas
- Publish 200 messages quickly to inference-requests topic (`gcloud pubsub topics publish` in a loop)
- kubectl get pods -w — workers appear within 30s
- GPU node provisioned by GKE autoscaler (~3-5min cold start)
- Drain queue, watch pods + GPU node scale to 0 (~10min after last pod)
- Tune `cooldownPeriod` and threshold based on observed behavior

**Day 16 · May 22 Thu · Cloud Logging + Monitoring**
- GKE managed Cloud Logging is on by default — verify logs in Logs Explorer, query by `request_id`
- No Fluent Bit install needed (vs AWS Day 19)
- Set up Log-based Metric for inference latency (parsed from worker JSON logs) if not already exporting via OTel

**Day 17 · May 23 Fri · Cloud Monitoring dashboard**
- `google_monitoring_dashboard` resource: panels for Pub/Sub backlog, worker pod count, GPU node count
- Custom metric from worker: `inference_latency_ms` via OpenTelemetry → Cloud Monitoring (or skip OTel and use a Log-based Metric)
- Add p50/p95 latency widget — should show <50ms typical for Merlin on T4
- terraform apply

**Day 18 · May 24 Sat · Week 3 buffer**
- Cold-start test: 0 → first response, document time
- Note: 20GB image pull makes cold start slower than vLLM (Artifact Registry + private Google access helps)
- Fix issues, commit

---

### Week 4 — Polish + teardown

**Day 19 · May 25 Sun · Cloud Monitoring alarms**
- `google_monitoring_alert_policy`: Pub/Sub subscription backlog > 200 for 5min
- Alert: pod count = 0 when backlog > 0
- `google_monitoring_notification_channel` (email)
- Trigger alarm manually to test (publish 250+ messages with workers scaled to 0)

**Day 20 · May 26 Mon · Load test**
- locustfile.py: ramp 1 → 50 concurrent users
- Run load test against FastAPI
- Watch dashboard react in real time
- Screenshot at peak — measure throughput in requests/second

**Day 21 · May 27 Tue · Break it + fix it**
- Kill worker mid-batch — verify Pub/Sub redelivery (ack deadline expired)
- Publish 1000 messages — verify graceful backlog
- Delete FastAPI pod, verify self-heal
- Document every failure mode

**Day 22 · May 28 Wed · Terraform cleanup**
- Descriptions on every resource, consistent naming
- Hardcoded values → variables with description and default
- Outputs: LoadBalancer IP, topic names, AR repo URL, dashboard URL
- terraform plan = zero changes

**Day 23 · May 29 Thu · README + architecture**
- Excalidraw diagram: client → FastAPI → Pub/Sub → KEDA → workers → Triton/Merlin
- README: problem, architecture, design decisions, AWS-vs-GCP comparison (the dual stack is the differentiator)
- Section: "Production maturity roadmap" — feature store, NVTabular pipelines, Triton ensembles, regional cluster, multi-region NAT
- Cost analysis: baseline + per 1M predictions, AWS-vs-GCP delta

**Day 24 · May 30 Fri · Final polish + share with team**
- Clean git history, meaningful commits
- 3-min Loom: autoscaling working live, end with example prediction
- Share GitHub repo with teammate before Merlin proposal
- Write "next steps" doc: how this scales to your team's actual use case

**Day 25 · May 31 Sat · Teardown**
- `gcloud artifacts docker images delete` for AR images (or empty repo)
- terraform destroy
- Manually delete GCS state bucket
- Verify zero orphaned resources, check final bill

---

## Key Things to Remember
- Terraform owns everything in GCP — `terraform destroy` should clean up entirely
- Outside Terraform: Docker builds/pushes, K8s app manifests during dev, kubectl debugging
- Use environment variables for everything cloud-specific (the GCP↔AWS port already proves the value)
- Workload Identity is the single biggest mental shift from AWS — read GCP's WI docs carefully on Day 6
- Don't add scope mid-project. Polish > new features.

---

## Continuing in a New Claude Chat

Paste this whole document into a new Claude conversation and ask whatever you need help with. Examples:
- "This is my project plan. Help me debug a Workload Identity binding I'm hitting on Day 6."
- "This is my project plan. Walk me through writing the worker.py for Day 12 with the Pub/Sub client."
- "This is my project plan. KEDA isn't scaling on the gcp-pubsub trigger — help me debug."

Claude will have full context for the architecture, scope, and design decisions.
