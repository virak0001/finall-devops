# Bootstrap — the S3 bucket every other state in this repo lives in.
#
#   make bootstrap      once per account, ~1 min, cents per month
#
# This root's own state stays local (bootstrap/terraform.tfstate, gitignored):
# it cannot keep its state in a bucket it has not created yet. That is safe
# because it holds one thing. Lose the file and nothing breaks — the bucket
# keeps every other state; re-adopt it with
#
#   terraform -chdir=bootstrap import aws_s3_bucket.state <bucket-name>

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project_name" {
  type        = string
  description = "Prefix of the bucket name"
  default     = "upskill-devops"
}

variable "region" {
  type        = string
  description = "Region the bucket lives in — must match backend.hcl"
  default     = "us-east-1"
}

variable "aws_account_id" {
  type        = string
  description = "The account the bucket belongs to; the apply refuses any other"
  default     = "570417737010"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project    = var.project_name
      ManagedBy  = "terraform"
      Repository = "dev-finall/terraform/bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global across every AWS account; the account id is what
  # makes this one unclaimable by anybody else.
  bucket_name = "${var.project_name}-tfstate-${var.aws_account_id}"
}

resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "Credentials point at ${data.aws_caller_identity.current.account_id}, not ${var.aws_account_id}."
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Every environment's state is in here. Deleting it makes Terraform forget
  # everything it built, while all of it keeps running and billing.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.account_guard]
}

# Every write keeps the previous version, so a state corrupted by a bad apply
# or a botched `state rm` can be rolled back from the console.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Old versions are only for recovery. 90 days of them is plenty, and stops a
# busy repo accumulating thousands.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State holds secrets in plain text — certificate data, any password a
# resource was created with. Nothing about it is ever public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "bucket" {
  description = "The state bucket — what backend.hcl names"
  value       = aws_s3_bucket.state.bucket
}
