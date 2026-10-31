# Global — what every environment shares: one ECR repository per service.
#
#   make global-plan
#   make global-apply
#
# One registry, not one per environment, because a release is a promotion:
# the image Jenkins built and dev ran is the exact image uat accepts and prod
# runs — same digest, retagged never. Tags are IMMUTABLE (modules/registry),
# so "v1.4.2" can only ever mean one image.
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

  # Image tags are `git describe` output (3.0.6-2-g73bf736), so every image
  # falls under the "any other tag" rule. 50 per service is the rollback
  # window — a few cents of storage.
  keep_any_images = 50

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
