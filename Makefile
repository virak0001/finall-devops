SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# No default: this command builds and bills a whole environment, so which one
# has to be said out loud.
WORKSPACE ?=

SUB := $(MAKE) --no-print-directory WORKSPACE=$(WORKSPACE)

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*?## " } /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: check
check: ## Find what would stop a bring-up, in seconds: make check WORKSPACE=prod
	@scripts/preflight.sh "$(WORKSPACE)"

# Safe to re-run: every step updates what already exists. The apply goes
# straight through with no review, which is the point of one command. Use
# `make plan` in terraform/ when a change needs reading first.
.PHONY: up
up: check ## Build or update everything in one environment: make up WORKSPACE=prod
	@$(SUB) -C terraform myip-set >/dev/null
	@$(SUB) -C terraform plan
	@$(SUB) -C terraform apply-plan
	@$(SUB) -C cluster up

# The cluster goes first: Terraform does not know about the ALB, and a leftover
# one stops the VPC deleting. The wait is for external-dns, which needs a cycle
# to remove the DNS records while it still exists. Each step keeps its own
# confirmation prompt, so this asks three times.
.PHONY: down
down: ## Delete everything in one environment: make down WORKSPACE=prod
	@test -f "terraform/env/$(WORKSPACE).tfvars" || { echo "error: name an environment: make down WORKSPACE=<env>"; exit 1; }
	@$(SUB) -C cluster platform-pull
	@$(SUB) -C cluster kubeconfig
	@$(SUB) -C cluster cluster-down
	@echo "Waiting 60 seconds for external-dns to remove the DNS records..."
	@sleep 60
	@$(SUB) -C terraform destroy
