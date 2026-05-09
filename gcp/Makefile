TERRAFORM_DIR := terraform
CLUSTER       := merlins-lair-gke

# Pulled out of terraform.tfvars so `make kubeconfig` works without a tf state read.
# Override on the command line if needed: `make kubeconfig PROJECT_ID=xxx ZONE=yyy`
PROJECT_ID    ?= $(shell awk -F= '/^project_id/ {gsub(/[" ]/, "", $$2); print $$2}' $(TERRAFORM_DIR)/terraform.tfvars 2>/dev/null)
ZONE          ?= europe-west1-b

.PHONY: help up down plan apply destroy kubeconfig nodes status fmt validate ip auth

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: apply kubeconfig nodes  ## Bring the stack up + wire kubectl

down:  ## Tear down ALL GCP resources (daily cost-saver)
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

plan:  ## terraform plan
	cd $(TERRAFORM_DIR) && terraform plan

apply:  ## terraform apply (no kubectl setup)
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve

destroy: down  ## Alias for down

auth:  ## One-time gcloud auth (login + ADC for terraform)
	gcloud auth login
	gcloud auth application-default login

kubeconfig:  ## Refresh local kubeconfig for the cluster
	@if [ -z "$(PROJECT_ID)" ]; then echo "PROJECT_ID not set — fill terraform/terraform.tfvars or pass PROJECT_ID=..."; exit 1; fi
	gcloud container clusters get-credentials $(CLUSTER) --zone $(ZONE) --project $(PROJECT_ID)

nodes:  ## kubectl get nodes
	kubectl get nodes -o wide

status:  ## Cluster + node status (works even if cluster is down)
	@gcloud container clusters describe $(CLUSTER) --zone $(ZONE) --project $(PROJECT_ID) \
		--format='value(status)' 2>/dev/null \
		|| echo "cluster: not deployed"
	@kubectl get nodes 2>/dev/null || true

fmt:  ## terraform fmt
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

validate:  ## terraform validate
	cd $(TERRAFORM_DIR) && terraform validate

ip:  ## Print my current public IPv4 (paste into terraform.tfvars if it changed)
	@curl -s -4 ifconfig.me && echo
