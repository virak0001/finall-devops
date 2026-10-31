# S3 backend settings, passed by `make init` (terraform init -backend-config=backend.hcl).
#
# The bucket is created by bootstrap/ — `make bootstrap` — and must exist
# before the first init. Workspaces land at env:/<workspace>/<key>, so dev,
# uat and prod each get their own state file. global/ overrides the key.

bucket       = "upskill-devops-tfstate-570417737010"
key          = "environments/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true # S3-native locking — no DynamoDB table
