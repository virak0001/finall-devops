# Jenkins + SonarQube on one EC2 instance, in Docker.
#
#   make up       everything, from nothing to two URLs
#   make pause    stop the instance, keep the data   (~$69/mo → ~$6/mo)
#   make destroy  remove it all                       (→ $0)

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

TF_DIR    := $(CURDIR)/terraform
WORKSPACE ?= dev
VARS      := env/$(WORKSPACE).tfvars

# Read from the tfvars so it cannot disagree with what Terraform used. Only the
# aws CLI calls below need it.
REGION := $(shell sed -n 's/^[[:space:]]*region[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' $(TF_DIR)/env/$(WORKSPACE).tfvars 2>/dev/null | head -1)

TF_OUT := TF_WORKSPACE=$(WORKSPACE) terraform -chdir=$(TF_DIR) output -raw

define tf
	@test -f "$(TF_DIR)/$(VARS)" || { \
	  echo "error: no $(VARS) — environments are: $$(ls $(TF_DIR)/env/*.tfvars 2>/dev/null | xargs -n1 basename | sed 's/.tfvars//' | tr '\n' ' ')"; \
	  exit 1; }
	@cd $(TF_DIR) && terraform workspace select -or-create $(WORKSPACE) >/dev/null
	cd $(TF_DIR) && terraform $(1)
endef

define need_instance
	@ip="$$($(TF_OUT) public_ip 2>/dev/null)"; test -n "$$ip" || { \
	  echo "error: no instance for workspace '$(WORKSPACE)'."; \
	  echo "         make apply WORKSPACE=$(WORKSPACE)"; \
	  exit 1; }
endef

# ─── Help ────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@printf '\nUsage: make \033[36m<target>\033[0m WORKSPACE=<env>\n\n'
	@awk 'BEGIN { FS = ":.*?## " } \
	  /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nWORKSPACE is \033[36m%s\033[0m\n\n' "$(WORKSPACE)"

# ─── Build ───────────────────────────────────────────────────────────────────

.PHONY: up
up: ## Everything: instance, Docker, Jenkins and SonarQube (~6 minutes)
	@$(MAKE) --no-print-directory myip WORKSPACE=$(WORKSPACE)
	@$(MAKE) --no-print-directory apply WORKSPACE=$(WORKSPACE)
	@$(MAKE) --no-print-directory deploy WORKSPACE=$(WORKSPACE)

.PHONY: init
init: ## Providers + the S3 state backend (once per machine, and after adding a provider)
	cd $(TF_DIR) && terraform init -input=false -backend-config=backend.hcl

.PHONY: check
check: ## fmt + validate — no AWS calls, no credentials
	cd $(TF_DIR) && terraform fmt -recursive -check -diff
	cd $(TF_DIR) && terraform validate

.PHONY: plan
plan: ## What would change
	$(call tf,plan -var-file=$(VARS) -out=tfplan)

.PHONY: apply
apply: ## Create or update the instance
	$(call tf,apply -var-file=$(VARS))

.PHONY: output
output: ## Addresses and ids Terraform produced
	$(call tf,output)

.PHONY: deploy
deploy: ## Copy docker/ up and start the stack — run after editing compose
	@scripts/deploy.sh $(WORKSPACE)

.PHONY: webhooks
webhooks: ## Point the service repos' GitHub webhooks at this Jenkins (needs gh auth login)
	@scripts/github-webhooks.sh $(WORKSPACE)

# ─── Access ──────────────────────────────────────────────────────────────────

.PHONY: url
url: ## Where Jenkins and SonarQube are
	$(need_instance)
	@echo "  Jenkins    $$($(TF_OUT) jenkins_url)"
	@echo "  SonarQube  $$($(TF_OUT) sonarqube_url)"

.PHONY: ssh
ssh: ## Shell on the instance
	$(need_instance)
	@$$($(TF_OUT) ssh_command)

.PHONY: logs
logs: ## Follow container logs (SERVICE=jenkins|sonarqube|db for one)
	$(need_instance)
	@$$($(TF_OUT) ssh_command) -t 'cd /opt/ci && docker compose logs -f --tail=100 $(SERVICE)'

.PHONY: ps
ps: ## What is running on the instance
	$(need_instance)
	@$$($(TF_OUT) ssh_command) 'cd /opt/ci && docker compose ps'

.PHONY: jenkins-password
jenkins-password: ## The initial admin password from the first boot
	$(need_instance)
	@$$($(TF_OUT) ssh_command) \
	  'docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null' \
	  || echo "(already through the setup wizard — the file is deleted then)"

.PHONY: myip
myip: ## Does your current IP still match the allowlist?
	@ip=$$(curl -s --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]'); \
	  test -n "$$ip" || { echo "error: could not reach checkip.amazonaws.com"; exit 1; }; \
	  allowed=$$(sed -n 's/^[[:space:]]*ssh_allowed_cidrs[[:space:]]*=[[:space:]]*//p' "$(TF_DIR)/$(VARS)"); \
	  printf '  your IP now: %s\n  allowlisted: %s\n\n' "$$ip" "$$allowed"; \
	  if [[ "$$allowed" == *"$$ip/32"* ]]; then echo "  match"; else \
	    echo "  NO MATCH. SSH and both web UIs will hang rather than refuse —"; \
	    echo "  a security group drops unmatched packets instead of rejecting them."; \
	    echo; echo "      make myip-set WORKSPACE=$(WORKSPACE) && make apply WORKSPACE=$(WORKSPACE)"; \
	    exit 1; fi

.PHONY: myip-set
myip-set: ## Write your current IP into the allowlist
	@ip=$$(curl -s --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]'); \
	  test -n "$$ip" || { echo "error: could not reach checkip.amazonaws.com"; exit 1; }; \
	  sed -i "s|^ssh_allowed_cidrs.*|ssh_allowed_cidrs = [\"$$ip/32\"]|" "$(TF_DIR)/$(VARS)"; \
	  grep -n '^ssh_allowed_cidrs' "$(TF_DIR)/$(VARS)" | sed 's/^/  /'; \
	  echo; echo "  now: make apply WORKSPACE=$(WORKSPACE)"

# ─── Cost ────────────────────────────────────────────────────────────────────
# Stopping keeps the root volume, so Jenkins jobs and SonarQube history
# survive. The Elastic IP means the address is the same when it comes back —
# which matters, because Jenkins stores its own URL and SonarQube's webhook
# points at it.

.PHONY: pause
pause: ## Stop the instance, keep the data (~$69/mo -> ~$6/mo)
	$(need_instance)
	@id="$$($(TF_OUT) instance_id)"; \
	  aws ec2 stop-instances --region $(REGION) --instance-ids "$$id" \
	    --query 'StoppingInstances[].CurrentState.Name' --output text | sed 's/^/    /'; \
	  echo; echo 'Still billing: the 25 GB volume (~$$2/mo) and the Elastic IP (~$$3.65/mo).'; \
	  echo "    make resume WORKSPACE=$(WORKSPACE)"

.PHONY: resume
resume: ## Start it again
	$(need_instance)
	@id="$$($(TF_OUT) instance_id)"; \
	  aws ec2 start-instances --region $(REGION) --instance-ids "$$id" \
	    --query 'StartingInstances[].CurrentState.Name' --output text | sed 's/^/    /'; \
	  echo; echo "Containers restart themselves (restart: unless-stopped)."; \
	  echo "SonarQube takes 2-3 minutes before it answers."; \
	  echo "    make url WORKSPACE=$(WORKSPACE)"

.PHONY: destroy
destroy: ## Remove everything. Jenkins jobs and SonarQube history go with it.
	@echo "This deletes the instance and its volume — every Jenkins job,"
	@echo "every SonarQube project and all analysis history."
	@read -p "Type the workspace name to confirm: " c; \
	  if [[ "$$c" != "$(WORKSPACE)" ]]; then echo "aborted"; exit 1; fi
	$(call tf,destroy -var-file=$(VARS))
