# S3 backend settings, passed by `make init` (terraform init -backend-config=backend.hcl).
#
# The same bucket as the platform (dev-finall/terraform/bootstrap creates it),
# under its own prefix: workspaces land at jenkins-sonarqube/<workspace>/<key>,
# so they never collide with the platform's env:/<workspace>/ states.

bucket               = "upskill-devops-tfstate-570417737010"
workspace_key_prefix = "jenkins-sonarqube"
key                  = "terraform.tfstate"
region               = "us-east-1"
encrypt              = true
use_lockfile         = true # S3-native locking — no DynamoDB table
