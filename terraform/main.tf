# Root configuration — one environment: its VPC and its EKS cluster.
#
#   make apply      WORKSPACE=dev  → VPC, EKS, node group, add-ons, pod identities
#   make kubeconfig WORKSPACE=dev  → kubectl pointed at it
#
# Three roots, applied in this order the first time and rarely after:
#
#   bootstrap/   the S3 bucket every state lives in          once per account
#   global/      ECR — shared, so one image moves dev → prod  once per account
#   .            this — one environment per workspace         per environment
#
# The registry is not here. A release promotes the SAME immutable image from
# dev to uat to prod; if each workspace owned its repositories they would
# collide on name in one account, and promoting would mean rebuilding.

terraform {
  required_version = ">= 1.10.0" # S3-native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bucket, key and locking come from backend.hcl — `make init` passes it.
  # Each workspace's state lands at env:/<workspace>/<key> in the bucket, so
  # dev, uat and prod never share a state file.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = local.environment
      ManagedBy   = "terraform"
      Repository  = "dev-finall/terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # The workspace IS the environment. `make apply WORKSPACE=dev` selects the
  # dev state and the dev variables together, so there is no way to apply prod
  # sizing onto dev's resources — the mistake a plain `environment` variable
  # leaves open, because nothing stops you passing prod.tfvars while the dev
  # state is selected.
  environment = terraform.workspace

  name_prefix  = "${var.project_name}-${local.environment}"
  cluster_name = coalesce(var.cluster_name, local.name_prefix)
}

# Terraform has no validation block for a workspace name, so this is the check.
# It fails at plan time, before anything is created.
resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = contains(["dev", "uat", "prod"], terraform.workspace)
      error_message = <<-ERR
        Workspace "${terraform.workspace}" is not one of dev, uat, prod.

        The 'default' workspace is deliberately not usable: it is the one you
        land in by accident, and it is where people apply prod changes while
        thinking they are somewhere else.

            make plan WORKSPACE=dev
      ERR
    }
  }
}

# Which AWS account the credentials in your shell actually point at.
#
# Without this, changing credentials does not fail — it succeeds against the
# wrong account. Terraform finds none of the resources in its state, plans to
# create all of them, and builds a complete second environment while the first
# one keeps running and billing.
#
# Only checked when aws_account_id is set in the tfvars. Null skips it.
resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition = (
        var.aws_account_id == null ||
        var.aws_account_id == data.aws_caller_identity.current.account_id
      )
      error_message = <<-ERR
        Wrong AWS account.

          credentials point at   ${data.aws_caller_identity.current.account_id}
          ${terraform.workspace} expects            ${coalesce(var.aws_account_id, "(unset)")}

        Applying now would build a second copy of ${terraform.workspace} in the
        wrong account, while the real one keeps running and billing.

            aws sts get-caller-identity --query Account --output text

        Fix the credentials, or change aws_account_id in
        terraform/env/${terraform.workspace}.tfvars if the move is deliberate.
      ERR
    }
  }
}

# ─── Network ─────────────────────────────────────────────────────────────────

module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  environment        = local.environment
  region             = var.region
  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  single_nat_gateway = var.single_nat_gateway
  enable_flow_logs   = var.enable_flow_logs
  tags               = var.tags
}

# ─── Cluster ─────────────────────────────────────────────────────────────────
# There is no load balancer module any more. The AWS Load Balancer Controller,
# running in the cluster, creates the ALB from an Ingress — its listeners,
# rules, health checks and certificate all come from the Ingress annotations,
# and its targets are pod IPs directly rather than a NodePort on every node.
# external-dns then points the hostname at it. Both get their AWS permissions
# from module.eks.pod_identities; both are installed by the cluster project.

module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  environment        = local.environment
  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  api_allowed_cidrs    = var.api_allowed_cidrs
  admin_principal_arns = var.admin_principal_arns
  team_access          = var.team_access

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size

  cluster_log_types         = var.cluster_log_types
  log_retention_days        = var.log_retention_days
  enable_container_insights = var.enable_container_insights

  route53_zone_arn = local.dns_enabled ? data.aws_route53_zone.this[0].arn : null

  tags = var.tags
}

# ─── WAF ─────────────────────────────────────────────────────────────────────
# A web ACL for the ALB above. Terraform cannot attach it — the ALB is the
# Load Balancer Controller's — so its ARN goes to SSM as waf_acl_arn
# (platform.tf) and every Ingress in the ALB group names it; the controller
# associates it. Your own IP (api_allowed_cidrs) is exempt from the rate limit
# only, so `make load-test` is not blocked by its own WAF.

module "waf" {
  source = "./modules/waf"
  count  = var.waf_enabled ? 1 : 0

  project_name = var.project_name
  environment  = local.environment

  rate_limit              = var.waf_rate_limit
  rate_limit_exempt_cidrs = var.api_allowed_cidrs

  # Argo CD's API shares this ALB and posts whole manifests, over the common
  # rule set's 8 KB body limit.
  count_only_common_rules = ["SizeRestrictions_BODY"]

  tags = var.tags
}

# ─── Monitoring ──────────────────────────────────────────────────────────────
# The dashboard, the alarms and the ALB's access-log bucket for this
# environment. Alarms go to global/'s SNS topic — one place to subscribe an
# email for everything. That topic is named after global/'s project
# (shared_project_name), not this environment's: prod's project_name differs.
# Its ARN is built rather than looked up, so planning an environment does not
# need global/ applied first.
#
# The ALB is named after the cluster by the cluster project's Ingresses, which
# is how the dashboard finds its metrics; the bucket name reaches those
# Ingresses through SSM (platform.tf, alb_logs_bucket).

module "monitoring" {
  source = "./modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  project_name = var.project_name
  environment  = local.environment
  cluster_name = local.cluster_name
  alb_name     = local.cluster_name

  alarm_topic_arn = "arn:${data.aws_partition.current.partition}:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${var.shared_project_name}-alerts"

  # From outside, over DNS, TLS, the WAF and the ALB — what a user sees.
  uptime_checks = local.dns_enabled ? {
    site     = { fqdn = var.site_hostname, path = "/" }
    auth-api = { fqdn = var.site_hostname, path = "/api/auth/health" }
  } : {}

  container_insights_enabled = var.enable_container_insights
  waf_enabled                = var.waf_enabled
  waf_web_acl_name           = var.waf_enabled ? module.waf[0].web_acl_name : ""

  alb_access_logs    = var.alb_access_logs
  log_retention_days = var.log_retention_days

  cpu_alarm_threshold    = var.cpu_alarm_threshold
  memory_alarm_threshold = var.memory_alarm_threshold

  extra_alarm_arns = ["arn:${data.aws_partition.current.partition}:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:${var.shared_project_name}-deployment-failed"]

  tags = var.tags
}

# ─── What used to live here ──────────────────────────────────────────────────
# ECR moved to global/. These tell Terraform to forget the repositories in
# this workspace's state WITHOUT deleting them — they still hold every image —
# so global/ can import them. The old push policy is not listed: it is simply
# destroyed, and global/ creates its replacement.
#
# Delete these blocks once every workspace has applied past them.

removed {
  from = module.registry.aws_ecr_repository.this

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.registry.aws_ecr_lifecycle_policy.this

  lifecycle {
    destroy = false
  }
}
