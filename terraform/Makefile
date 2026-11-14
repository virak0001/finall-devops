SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

TF_DIR    := $(CURDIR)
WORKSPACE ?= dev
VARS      := env/$(WORKSPACE).tfvars
BACKEND   := -backend-config=backend.hcl
REGION    := $(shell sed -n 's/^[[:space:]]*region[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' $(TF_DIR)/$(VARS) 2>/dev/null | head -1)
PROJECT   := $(shell sed -n 's/^[[:space:]]*project_name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' $(TF_DIR)/$(VARS) 2>/dev/null | head -1)
SECRETS_IMPORT := secrets_import.tf
LOGS_IMPORT    := logs_import.tf

define tf
	@test -f "$(TF_DIR)/$(VARS)" || { \
	  echo "error: no $(VARS) — environments are: $$(ls $(TF_DIR)/env/*.tfvars | xargs -n1 basename | sed 's/.tfvars//' | tr '\n' ' ')"; \
	  exit 1; }
	@cd $(TF_DIR) && terraform workspace select -or-create $(WORKSPACE) >/dev/null
	cd $(TF_DIR) && terraform $(1)
endef

# ─── Help ────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@printf '\nUsage: make \033[36m<target>\033[0m WORKSPACE=<env>\n'
	@awk 'BEGIN { FS = ":.*?## " } \
	  /^# \xe2\x94\x80\xe2\x94\x80\xe2\x94\x80 / { \
	    line = substr($$0, 13); i = index(line, " \xe2\x94\x80"); \
	    if (i > 0) line = substr(line, 1, i - 1); \
	    pending = line; next } \
	  /^[a-zA-Z0-9_-]+:.*?## / { \
	    if (pending != "") { printf "\n\033[1m%s\033[0m\n", pending; pending = "" } \
	    printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nWORKSPACE is \033[36m%s\033[0m. Available: ' "$(WORKSPACE)"
	@ls $(TF_DIR)/env/*.tfvars 2>/dev/null | xargs -n1 basename | sed 's/.tfvars//' | tr '\n' ' '
	@printf '\n\n'

# ─── Core loop ───────────────────────────────────────────────────────────────

.PHONY: init
init: ## Download providers and connect the S3 backend (once per machine; needs `make bootstrap` first)
	cd $(TF_DIR) && terraform init -input=false $(BACKEND)

.PHONY: migrate-state
migrate-state: ## Move local terraform.tfstate.d/* states into the S3 bucket (once, after bootstrap)
	cd $(TF_DIR) && terraform init -migrate-state $(BACKEND)

.PHONY: plan
plan: secrets-restore logs-adopt ## Show what would change: make plan WORKSPACE=dev
	$(call tf,plan -var-file=$(VARS) -out=tfplan)

.PHONY: apply
apply: secrets-restore logs-adopt ## Apply the plan you just reviewed (asks before changing anything)
	$(call tf,apply -var-file=$(VARS))

# A destroy leaves each secret scheduled for deletion, with its name reserved
# for secret_recovery_window_days, and creating that name fails until then. So
# take back any still waiting (restore keeps the value), and adopt any secret
# that exists but is not in state.
#
# Import blocks, not `terraform import`: that command cannot evaluate the
# config against an empty state, which is what a rebuild starts from. The file
# is written fresh each run and is empty of blocks once state holds the secrets.
.PHONY: secrets-restore
secrets-restore: ## Restore this workspace's deleted secrets and adopt them, so a rebuild can reuse the names
	@cd $(TF_DIR) && terraform workspace select -or-create $(WORKSPACE) >/dev/null
	@cd $(TF_DIR) && rm -f $(SECRETS_IMPORT) && \
	  managed="$$(terraform state list 2>/dev/null || true)" && \
	  aws secretsmanager list-secrets --region $(REGION) --include-planned-deletion \
	    --filters Key=name,Values=$(PROJECT)/$(WORKSPACE)/ \
	    --query 'SecretList[].[Name,ARN,DeletedDate]' --output text | \
	  while read -r name arn deleted; do \
	    if [[ "$$deleted" != "None" ]]; then \
	      echo "restoring $$name"; \
	      aws secretsmanager restore-secret --region $(REGION) --secret-id "$$arn" >/dev/null </dev/null; \
	    fi; \
	    address="aws_secretsmanager_secret.team[\"$${name##*/}\"]"; \
	    if ! grep -qxF "$$address" <<<"$$managed"; then \
	      echo "adopting $$name"; \
	      printf 'import {\n  to = %s\n  id = "%s"\n}\n' "$$address" "$$arn" >> $(SECRETS_IMPORT); \
	    fi; \
	  done

# Fluent Bit keeps writing while a destroy runs, and on a missing log group it
# makes one: no retention, not in state. The next apply then fails with
# ResourceAlreadyExistsException. Adopt each such group, so the apply takes it
# over and puts the retention back instead of failing.
.PHONY: logs-adopt
logs-adopt: ## Adopt Container Insights log groups a destroy left behind
	@cd $(TF_DIR) && terraform workspace select -or-create $(WORKSPACE) >/dev/null
	@cd $(TF_DIR) && rm -f $(LOGS_IMPORT) && \
	  managed="$$(terraform state list 2>/dev/null || true)" && \
	  prefix="/aws/containerinsights/$(PROJECT)-$(WORKSPACE)/" && \
	  aws logs describe-log-groups --region $(REGION) --log-group-name-prefix "$$prefix" \
	    --query 'logGroups[].logGroupName' --output text | tr '\t' '\n' | \
	  while read -r name; do \
	    [[ -n "$$name" && "$$name" != "None" ]] || continue; \
	    address="module.eks.aws_cloudwatch_log_group.container_insights[\"$${name#"$$prefix"}\"]"; \
	    if ! grep -qxF "$$address" <<<"$$managed"; then \
	      echo "adopting $$name"; \
	      printf 'import {\n  to = %s\n  id = "%s"\n}\n' "$$address" "$$name" >> $(LOGS_IMPORT); \
	    fi; \
	  done

.PHONY: apply-plan
apply-plan: ## Apply exactly the saved tfplan from `make plan` — no second prompt, no drift
	$(call tf,apply tfplan)

.PHONY: destroy
destroy: ## Tear the workspace down — VPC, cluster, nodes. ECR is global/'s and survives.
	@echo "This destroys everything Terraform created in workspace '$(WORKSPACE)'."
	@echo
	@echo "It does NOT destroy what the cluster created in AWS: the ALB the load"
	@echo "balancer controller made from an Ingress, and EBS volumes behind"
	@echo "PersistentVolumeClaims. Those keep billing, a leftover ALB holds ENIs"
	@echo "that stop the VPC deleting, and it holds the certificate too, so the"
	@echo "destroy fails on both. Delete every Ingress and PVC first:"
	@echo
	@echo "    make -C ../cluster cluster-down WORKSPACE=$(WORKSPACE)"
	@echo
	@echo "The secrets KMS key is scheduled for deletion, not deleted: 7 days in"
	@echo "which \`aws kms cancel-key-deletion\` can still bring it back."
	@echo
	@read -p "Type the workspace name to confirm: " c; \
	  if [[ "$$c" != "$(WORKSPACE)" ]]; then echo "aborted"; exit 1; fi
	@rm -f $(TF_DIR)/$(SECRETS_IMPORT) $(TF_DIR)/$(LOGS_IMPORT)
	$(call tf,destroy -var-file=$(VARS))

.PHONY: output
output: ## Print this workspace's outputs
	$(call tf,output)

.PHONY: refresh
refresh: ## Re-read reality into state, without changing anything
	$(call tf,refresh -var-file=$(VARS))

# ─── Workspaces ──────────────────────────────────────────────────────────────

.PHONY: workspaces
workspaces: ## List workspaces, which is selected, and how much each holds
	@cd $(TF_DIR) && terraform workspace list -no-color | while IFS= read -r line; do \
	  [[ -n "$${line// }" ]] || continue; \
	  if [[ "$$line" == '*'* ]]; then mark='->'; else mark='  '; fi; \
	  w=$$(echo "$$line" | tr -d '* '); \
	  n=$$(TF_WORKSPACE=$$w terraform state list 2>/dev/null | grep -vc '^data\.' || true); \
	  if [[ "$$n" -gt 0 ]]; then held="$$n resources"; else held='empty'; fi; \
	  if [[ -f "$(TF_DIR)/env/$$w.tfvars" ]]; then env='';  else env='  (no env/'"$$w"'.tfvars — not usable)'; fi; \
	  printf '%s %-10s %-14s%s\n' "$$mark" "$$w" "$$held" "$$env"; \
	done

.PHONY: current
current: ## Show what WORKSPACE would build, selecting it first
	@test -f "$(TF_DIR)/$(VARS)" || { echo "error: no $(VARS)"; exit 1; }
	@cd $(TF_DIR) && terraform workspace select -or-create $(WORKSPACE) >/dev/null
	@cd $(TF_DIR) && printf 'workspace: %s\n' "$$(terraform workspace show)"
	@printf 'varfile:   %s\n\n' "$(VARS)"
	@grep -vE '^\s*(#|$$)' $(TF_DIR)/$(VARS) | sed 's/^/  /'

# ─── Checks ──────────────────────────────────────────────────────────────────

.PHONY: fmt
fmt: ## Rewrite .tf files to canonical formatting
	cd $(TF_DIR) && terraform fmt -recursive

.PHONY: validate
validate: ## Check the configuration is internally consistent (no AWS calls, no credentials)
	cd $(TF_DIR) && terraform validate

.PHONY: check
check: fmt validate ## fmt + validate, the fast loop while editing

.PHONY: graph
graph: ## Write a dependency graph to graph.svg (needs graphviz)
	cd $(TF_DIR) && terraform graph | dot -Tsvg > $(CURDIR)/graph.svg
	@echo "wrote graph.svg"

# ─── Access ──────────────────────────────────────────────────────────────────

.PHONY: myip
myip: ## Check whether your current public IP may reach this cluster's Kubernetes API
	@test -f "$(TF_DIR)/$(VARS)" || { echo "error: no $(VARS)"; exit 1; }
	@ip=$$(curl -s --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]'); \
	  test -n "$$ip" || { echo "error: could not reach checkip.amazonaws.com — are you online?"; exit 1; }; \
	  allowed=$$(sed -n 's/^[[:space:]]*api_allowed_cidrs[[:space:]]*=[[:space:]]*//p' "$(TF_DIR)/$(VARS)" | head -1); \
	  printf '  your IP now: %s\n  allowlisted: %s\n\n' "$$ip" "$$allowed"; \
	  if [[ "$$allowed" == *"$$ip/32"* ]]; then \
	    echo "  match — kubectl will reach the API."; \
	  else \
	    echo "  NO MATCH. kubectl will hang rather than fail — the endpoint drops"; \
	    echo "  requests from outside the list instead of refusing them."; \
	    echo; \
	    echo "      make myip-set WORKSPACE=$(WORKSPACE)   # writes it to $(VARS)"; \
	    echo; \
	    echo "  Then, ONLY if the cluster is running now:"; \
	    echo "      make apply    WORKSPACE=$(WORKSPACE)   # ~1 min, the cluster is updated in place"; \
	    echo "  If it is destroyed, stop there — the next plan/apply-plan picks it up."; \
	    echo "  (make apply on a destroyed environment builds all of it.)"; \
	    exit 1; \
	  fi

.PHONY: myip-set
myip-set: ## Write your current public IP into this workspace's api_allowed_cidrs
	@test -f "$(TF_DIR)/$(VARS)" || { echo "error: no $(VARS)"; exit 1; }
	@ip=$$(curl -s --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]'); \
	  test -n "$$ip" || { echo "error: could not reach checkip.amazonaws.com — are you online?"; exit 1; }; \
	  line="api_allowed_cidrs = [\"$$ip/32\"]"; \
	  sed -i "s|^api_allowed_cidrs.*|$$line|" "$(TF_DIR)/$(VARS)"; \
	  grep -n '^api_allowed_cidrs' "$(TF_DIR)/$(VARS)" | sed 's/^/  /'; \
	  echo; \
	  echo "  Nothing has changed in AWS yet. Apply it:"; \
	  echo "      make apply WORKSPACE=$(WORKSPACE)"

.PHONY: cost
cost: ## What this workspace runs to per month, from the notes in its tfvars
	@grep -E '^\s*#\s*(cost|~\$$)' $(TF_DIR)/$(VARS) | sed 's/^\s*#\s*/  /' || \
	  echo "  no cost notes in $(VARS)"

.PHONY: kubeconfig
kubeconfig: ## Point kubectl at this workspace's cluster (context named after the cluster)
	@test -f "$(TF_DIR)/$(VARS)" || { echo "error: no $(VARS)"; exit 1; }
	@cd $(TF_DIR) && terraform workspace select $(WORKSPACE) >/dev/null
	@cd $(TF_DIR) && name=$$(terraform output -raw cluster_name 2>/dev/null) || { \
	  echo "error: no cluster in workspace '$(WORKSPACE)' yet — make apply WORKSPACE=$(WORKSPACE)"; exit 1; }; \
	  aws eks update-kubeconfig --region $(REGION) --name "$$name" --alias "$$name"; \
	  kubectl --context "$$name" get nodes

# ─── Shared roots ────────────────────────────────────────────────────────────
# Applied once per account, before any workspace. No WORKSPACE — each has one
# state.

.PHONY: bootstrap
bootstrap: ## Create the S3 state bucket (once per account, before `make init`)
	cd $(TF_DIR)/bootstrap && terraform init -input=false && terraform apply

.PHONY: global-init
global-init: ## Connect global/ (ECR) to the S3 backend
	cd $(TF_DIR)/global && terraform init -input=false -backend-config=../backend.hcl -backend-config=key=global/terraform.tfstate

.PHONY: global-plan
global-plan: ## Show what would change in the shared ECR registry
	cd $(TF_DIR)/global && terraform plan -out=tfplan

.PHONY: global-apply
global-apply: ## Apply the shared ECR registry (asks before changing anything)
	cd $(TF_DIR)/global && terraform apply

# ─── Housekeeping ────────────────────────────────────────────────────────────

.PHONY: clean
clean: ## Remove saved plans and the rendered graph
	rm -f $(TF_DIR)/tfplan $(TF_DIR)/global/tfplan $(TF_DIR)/$(SECRETS_IMPORT) $(CURDIR)/graph.svg
