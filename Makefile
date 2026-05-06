TERRAFORM_DIR := terraform
REGION        := eu-west-1
CLUSTER       := merlins-lair-eks

.PHONY: help up down plan apply destroy kubeconfig nodes status fmt validate ip

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: apply kubeconfig nodes  ## Bring the stack up + wire kubectl

down:  ## Tear down ALL AWS resources (daily cost-saver)
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

plan:  ## terraform plan
	cd $(TERRAFORM_DIR) && terraform plan

apply:  ## terraform apply (no kubectl setup)
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve

destroy: down  ## Alias for down

kubeconfig:  ## Refresh local kubeconfig for the cluster
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)

nodes:  ## kubectl get nodes
	kubectl get nodes -o wide

status:  ## Cluster + node status (works even if cluster is down)
	@aws eks describe-cluster --region $(REGION) --name $(CLUSTER) \
		--query 'cluster.status' --output text 2>/dev/null \
		|| echo "cluster: not deployed"
	@kubectl get nodes 2>/dev/null || true

fmt:  ## terraform fmt
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

validate:  ## terraform validate
	cd $(TERRAFORM_DIR) && terraform validate

ip:  ## Print my current public IPv4 (paste into terraform.tfvars if it changed)
	@curl -s -4 ifconfig.me && echo
