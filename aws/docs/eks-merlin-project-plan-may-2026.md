# EKS Merlin Inference Project — May 2026

## Background
I'm an infrastructure engineer with 3 years of experience pivoting toward AI infrastructure. I'm building a personal POC over the month of May 2026 to demonstrate I can deploy GPU-based ML inference on Kubernetes with autoscaling. Working 3 hours/day, 7 days a week. Budget: ~$130-160 for AWS for the month.

## Goal
Deploy NVIDIA Merlin (recommender system inference) on EKS with KEDA autoscaling, all infrastructure managed by Terraform. The goal is to have a working POC before my teammate proposes Merlin at work, so I can take ownership of the deployment when the time comes.

## Architecture
- Client → FastAPI (LoadBalancer Service) → SQS request queue → KEDA-scaled worker pods → Triton Inference Server with Merlin DLRM model on GPU → SQS response queue
- Cluster Autoscaler manages GPU nodes (scale to zero when idle)
- CloudWatch dashboards + alarms + Fluent Bit log forwarding
- Everything in Terraform except: Docker builds, app K8s manifests during dev, kubectl debugging
- `terraform destroy` cleans up everything at the end

## Stack
- AWS EKS (Kubernetes 1.30)
- Node groups: t3.medium x2 system (on-demand), g4dn.xlarge GPU (spot, min 0 max 3)
- Triton Inference Server with Merlin DLRM example (pre-trained on Criteo)
- Base image: `nvcr.io/nvidia/merlin/merlin-tensorflow:latest`
- KEDA for SQS-triggered autoscaling
- FastAPI for ingestion, Python worker for SQS polling
- Terraform with terraform-aws-modules/vpc and /eks community modules
- Remote state in S3 + DynamoDB

## Simplifications (deliberate, for POC scope)
- Pre-trained model only, no training pipeline
- Single Triton model, no ensembles
- No NVTabular preprocessing pipeline, no feature store
- Pre-computed Criteo features as input
- These are documented in README as "production maturity roadmap"

---

## Day-by-Day Plan

### Week 1 — Terraform foundation + EKS

**Day 1 · May 4 Sun · Project scaffold**
- Install: terraform, AWS CLI, kubectl, helm, docker
- AWS account + IAM admin user. Set $150 billing alert immediately
- Create free NGC account at ngc.nvidia.com (needed to pull Merlin images)
- Manually create S3 bucket + DynamoDB table for Terraform state (only manual AWS step)
- Scaffold: providers.tf, backend.tf, variables.tf, outputs.tf. Run terraform init

**Day 2 · May 5 Mon · VPC**
- vpc.tf using terraform-aws-modules/vpc — 3 public + 3 private subnets, NAT gateway
- Tag private subnets: kubernetes.io/role/internal-elb=1
- Tag public subnets: kubernetes.io/role/elb=1
- terraform apply, verify, commit

**Day 3 · May 6 Tue · EKS cluster**
- eks.tf using terraform-aws-modules/eks — K8s 1.30, private endpoint
- System node group: t3.medium x1, ON_DEMAND (POC: single node, no HA — saves ~$30/mo)
- GPU node group: g4dn.xlarge SPOT, min:0 max:3, taint nvidia.com/gpu=present:NoSchedule
- terraform apply (~15min). aws eks update-kubeconfig. kubectl get nodes

**Day 4 · May 7 Wed · ECR + SQS**
- ecr.tf for Triton/Merlin worker image (image will be ~20GB)
- sqs.tf for inference-requests, visibility_timeout=120, retention=1hr
- sqs.tf for inference-responses + dead-letter queues
- terraform apply, note queue URLs

**Day 5 · May 8 Thu · IAM + IRSA**
- aws_iam_openid_connect_provider for cluster OIDC
- aws_iam_role for app pods, trust policy scoped to namespace + service account
- aws_iam_policy: SQS send/receive/delete/get on both queues
- terraform apply, output role ARN

**Day 6 · May 9 Fri · K8s addons**
- helm_release for NVIDIA device plugin DaemonSet
- helm_release for Cluster Autoscaler with autoDiscovery
- aws_iam_role for Cluster Autoscaler service account
- terraform apply. kubectl describe node | grep nvidia.com/gpu

**Day 7 · May 10 Sat · Week 1 buffer**
- Fix any IAM/networking issues
- Check AWS bill
- Tags + descriptions on every resource
- Commit. terraform plan = no changes

---

### Week 2 — FastAPI + Merlin/Triton (kept simple)

**Day 8 · May 11 Sun · FastAPI app**
- FastAPI: POST /recommend accepts feature vector (Criteo schema), pushes to SQS, returns request_id
- GET /result/{request_id} polls inference-responses queue
- Dockerfile: python:3.11-slim base
- docker build + push to ECR

**Day 9 · May 12 Mon · FastAPI on EKS**
- k8s/fastapi-deployment.yaml: LoadBalancer Service, IRSA annotation
- Inject SQS URLs as env vars
- kubectl apply
- curl LoadBalancer URL, verify message in SQS

**Day 10 · May 13 Tue · Get Merlin example model**
- docker login nvcr.io with NGC API key
- Clone NVIDIA-Merlin/Merlin examples repo from GitHub
- Pick simplest pre-trained example: DLRM on Criteo (Triton-ready model files)
- Test the example locally with docker-compose first if possible

**Day 11 · May 14 Wed · Build Triton+Merlin image**
- Dockerfile: FROM nvcr.io/nvidia/merlin/merlin-tensorflow:latest as base
- COPY model files into /models with config.pbtxt (single model, no ensemble)
- COPY worker.py for SQS polling
- docker build (~20GB), push to ECR — start early

**Day 12 · May 15 Thu · Worker script**
- worker.py: poll inference-requests SQS → call Triton HTTP /v2/models/dlrm/infer → push result to inference-responses
- Triton uses KFServing v2 protocol — request body has 'inputs' array with name/shape/datatype/data
- Delete SQS message only after successful inference
- Structured JSON logging: job_id, latency_ms, prediction_score

**Day 13 · May 16 Fri · Worker on EKS + e2e test**
- k8s/worker-deployment.yaml: 0 replicas, GPU request, GPU toleration, IRSA
- kubectl apply, scale to 1, verify GPU: kubectl exec -- nvidia-smi
- Full flow test: POST /recommend → SQS → Triton infer → response. Expect <100ms inference
- Scale worker back to 0 after testing

**Day 14 · May 17 Sat · Week 2 buffer**
- Fix Triton config issues (config.pbtxt is fiddly first time)
- Clean up worker.py, push updated image
- Document the request/response schema with example payload

---

### Week 3 — KEDA autoscaling

**Day 15 · May 18 Sun · KEDA install**
- helm_release for KEDA, namespace=keda
- aws_iam_role for KEDA operator (sqs:GetQueueAttributes, GetQueueUrl)
- Pass IRSA ARN via helm_release set values
- terraform apply, verify keda pods Running, check logs for auth errors

**Day 16 · May 19 Mon · ScaledObject**
- k8s/scaledobject.yaml: trigger aws-sqs-queue, queueURL, awsRegion
- minReplicaCount:0, maxReplicaCount:3, threshold:50 (recsys is fast — higher threshold than LLM)
- scaleTargetRef → worker Deployment
- kubectl apply, kubectl get scaledobject (READY=True)

**Day 17 · May 20 Tue · Scale-out test**
- Confirm worker at 0 replicas
- Send 200 messages quickly to inference-requests queue
- kubectl get pods -w — workers appear within 30s
- Watch queue drain quickly (Triton + GPU is fast)

**Day 18 · May 21 Wed · Scale-to-zero test**
- Drain queue, watch pods scale to 0
- Watch GPU node terminate (~10min after last pod)
- Tune cooldownPeriod and threshold based on observed behavior
- Cost should drop to near-zero with no traffic

**Day 19 · May 22 Thu · Fluent Bit logging**
- helm_release for aws-for-fluent-bit DaemonSet
- aws_cloudwatch_log_group for /eks/recsys/fastapi and /worker
- CloudWatch logs permissions on node group IAM role
- Verify logs in CloudWatch Insights, query by request_id

**Day 20 · May 23 Fri · CloudWatch dashboard**
- aws_cloudwatch_dashboard: SQS depth, worker pod count, GPU node count
- Custom metric from worker: inference_latency_ms via boto3
- Add p50/p95 latency widget — should show <50ms typical for Merlin
- terraform apply

**Day 21 · May 24 Sat · Week 3 buffer**
- Cold-start test: 0 → first response, document time
- Note: 20GB image pull makes Merlin cold start slower than vLLM
- Fix issues, commit

---

### Week 4 — Polish + teardown

**Day 22 · May 25 Sun · CloudWatch alarms**
- aws_cloudwatch_metric_alarm: queue depth > 200 for 5min
- Alarm: pod count = 0 when queue depth > 0
- aws_sns_topic + email subscription
- Trigger alarm manually to test

**Day 23 · May 26 Mon · Load test**
- locustfile.py: ramp 1 → 50 concurrent users
- Run load test against FastAPI
- Watch dashboard react in real time
- Screenshot at peak — measure throughput in requests/second

**Day 24 · May 27 Tue · Break it + fix it**
- Kill worker mid-batch — verify SQS retry
- Send 1000 messages — verify graceful queue backup
- Delete FastAPI pod, verify self-heal
- Document every failure mode

**Day 25 · May 28 Wed · Terraform cleanup**
- Descriptions on every resource, consistent naming
- Hardcoded values → variables with description and default
- Outputs: LoadBalancer URL, queue URLs, ECR repo, dashboard URL
- terraform plan = zero changes

**Day 26 · May 29 Thu · README + architecture**
- Excalidraw diagram: client → FastAPI → SQS → KEDA → workers → Triton/Merlin
- README: problem, architecture, design decisions
- Section: "Production maturity roadmap" — feature store, NVTabular pipelines, Triton ensembles
- Cost analysis: baseline + per 1M predictions

**Day 27 · May 30 Fri · Final polish + share with team**
- Clean git history, meaningful commits
- 3-min Loom: autoscaling working live, end with example prediction
- Share GitHub repo with teammate before Merlin proposal
- Write "next steps" doc: how this scales to your team's actual use case

**Day 28 · May 31 Sat · Teardown**
- Empty ECR repos (aws ecr batch-delete-image)
- terraform destroy
- Manually delete S3 state bucket + DynamoDB table
- Verify zero orphaned resources, check final bill

---

## Key Things to Remember
- Terraform owns everything AWS — `terraform destroy` should clean up entirely
- Outside Terraform: Docker builds/pushes, K8s app manifests during dev, kubectl debugging
- Use environment variables for everything cloud-specific (makes future Azure port easier)
- IRSA debugging on Day 5 and Day 15 are the hardest single days — budget extra time
- Don't add scope mid-project. Polish > new features.

---

## Continuing in a New Claude Chat

Paste this whole document into a new Claude conversation and ask whatever you need help with. Examples:
- "This is my project plan. Help me debug an IRSA issue I'm hitting on Day 5."
- "This is my project plan. Walk me through writing the worker.py for Day 12."
- "This is my project plan. I'm stuck on KEDA not scaling — help me debug."

Claude will have full context for the architecture, scope, and design decisions.
