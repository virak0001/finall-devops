# Global — what every environment shares: one ECR repository per service.
#
#   make global-plan
#   make global-apply
#
# One registry, not one per environment, because a release is a promotion:
# the image Jenkins built and dev ran is the exact image uat accepts and prod
# runs — same digest, never rebuilt; each environment only adds its own name
# (dev-5a87e72, uat-5a87e72, prod-v1.4.2). Tags are IMMUTABLE
# (modules/registry), so a name can only ever mean one image.
#
# No workspace here. This root has one state, at global/terraform.tfstate in
# the state bucket.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "global"
      ManagedBy   = "terraform"
      Repository  = "dev-finall/terraform/global"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "Credentials point at ${data.aws_caller_identity.current.account_id}, not ${var.aws_account_id}."
    }
  }
}

resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = terraform.workspace == "default"
      error_message = "global/ has one state and no workspaces. Run `terraform -chdir=global workspace select default`."
    }
  }
}

# ─── Registry ────────────────────────────────────────────────────────────────

module "registry" {
  source = "../modules/registry"

  project_name      = var.project_name
  environment       = "global"
  repository_prefix = var.project_name
  repositories      = var.services

  # Empty: nodes pull with their own role's AmazonEC2ContainerRegistryPullOnly,
  # which covers every repository in the account. A repository policy naming
  # each environment's node role would have to change whenever a cluster is
  # rebuilt.
  pull_principal_arns = []

  # One image, a name per environment it reached: dev-5a87e72, then
  # uat-5a87e72, then prod-v1.0.8 (jenkins-sonarqube/shared-library/vars/
  # imageTag.groovy). prod- comes first, so an image prod ever ran is kept by
  # the prod- rule however many newer dev builds there are. The catch-all keeps
  # tags from before this scheme (1.0.7-14-g5a87e72, prod.v3.0.5).
  keep_by_tag_prefix = [
    { prefix = "prod-", keep = 100 },
    { prefix = "uat-", keep = 30 },
    { prefix = "dev-", keep = 30 },
  ]
  keep_any_images = 50

  tags = var.tags
}

# ─── Audit ───────────────────────────────────────────────────────────────────
# Who did what in this AWS account: one CloudTrail trail for every region and
# environment, kept in S3 for a year and searchable in CloudWatch for 90 days,
# plus security alarms (root used, IAM changed, logins failed, …) to the same
# SNS topic as the deployment alarm. Account-wide, so it lives here, not in an
# environment — and survives `make down`.

module "audit" {
  source = "../modules/audit"
  count  = var.enable_audit ? 1 : 0

  project_name    = var.project_name
  alarm_topic_arn = aws_sns_topic.alerts.arn

  tags = var.tags
}

# ─── Adopting the repositories dev used to own ───────────────────────────────
# Until this move, the dev workspace created these. Its `removed` blocks make
# dev forget them without deleting them, and these pick them up here — every
# image already pushed survives. An import of something already in this state
# is a no-op, so these are harmless after the first apply; delete them then.

import {
  for_each = toset(var.adopt_existing_repositories)

  to = module.registry.aws_ecr_repository.this[each.key]
  id = "${var.project_name}/${each.key}"
}

import {
  for_each = toset(var.adopt_existing_repositories)

  to = module.registry.aws_ecr_lifecycle_policy.this[each.key]
  id = "${var.project_name}/${each.key}"
}
