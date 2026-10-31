variable "project_name" {
  type        = string
  description = "Used for resource naming and tagging"
  default     = "ci"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.project_name))
    error_message = "Lowercase letters, digits and hyphens (2-25 chars)."
  }
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "aws_account_id" {
  type        = string
  description = <<-DESC
    The account this stack belongs to. Set it and every plan checks your
    credentials still point there, so a credential change cannot quietly build
    a second copy somewhere else. Null skips the check.
  DESC
  default     = null

  validation {
    condition     = var.aws_account_id == null || can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

# ─── Network ─────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the VPC. One /24 subnet is carved out of it."
  default     = "10.20.0.0/16"
}

variable "availability_zone" {
  type        = string
  description = "One AZ — there is one instance, so spreading buys nothing"
  default     = "us-east-1a"
}

# ─── Access ──────────────────────────────────────────────────────────────────

variable "ssh_allowed_cidrs" {
  type        = list(string)
  description = <<-DESC
    Who may reach SSH, Jenkins (8080) and SonarQube (9000).

    Your public egress IP, as AWS sees it — not a 192.168.x address:
      make myip       does this still match?
      make myip-set   rewrite it to your current one
  DESC

  validation {
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 would expose Jenkins to the internet. Use your own address."
  }

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0
    error_message = "At least one CIDR, or nothing can reach the instance."
  }
}

variable "ssh_public_key_path" {
  type        = string
  description = "Public key installed on the instance"
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Matching private key, used by make ssh and make deploy"
  default     = "~/.ssh/id_ed25519"
}

# ─── Instance ────────────────────────────────────────────────────────────────

variable "instance_type" {
  type        = string
  description = <<-DESC
    m7i-flex.large is 2 vCPU and 8 GiB, and is Free Tier eligible.

    8 GiB rather than 4: SonarQube runs Elasticsearch in-process and wants
    ~2 GiB to itself, Jenkins another ~1.5 GiB, Postgres ~0.3 GiB. On a 4 GiB
    box that fits with no headroom, and a concurrent build gets one of them
    OOM-killed — usually Elasticsearch, which looks like SonarQube crashing
    for no reason.

      aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true
  DESC
  default     = "m7i-flex.large"
}

variable "volume_size" {
  type        = number
  description = <<-DESC
    Root volume in GB. Holds the OS, Docker images (~2 GB for these three),
    Jenkins jobs and workspaces, and SonarQube's Postgres data.

    Jenkins workspaces are what fills this. `docker system prune` and a
    workspace cleanup step in the pipeline matter more than the number here.
  DESC
  default     = 25

  validation {
    condition     = var.volume_size >= 20
    error_message = "Below 20 GB the Docker images alone leave no room for builds."
  }
}

# ─── CI integration ──────────────────────────────────────────────────────────

variable "github_hook_cidrs" {
  type        = list(string)
  description = <<-DESC
    GitHub's webhook source ranges, allowed to reach Jenkins on 8080 only.

    GitHub publishes them, and changes them now and then:
      curl -s https://api.github.com/meta | jq -r '.hooks[]'
    IPv4 only — this VPC has no IPv6. Empty turns webhooks off; Jenkins then
    finds pushes on its periodic scan instead.
  DESC
  default = [
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20",
    "9.234.98.160/28",
    "9.234.98.176/28",
    "9.234.106.48/28",
  ]

  validation {
    condition     = !contains(var.github_hook_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 would expose Jenkins to the internet. Use GitHub's published hook ranges."
  }
}

variable "deployments_log_group" {
  type        = string
  description = "CloudWatch log group the pipelines write deployment records to — created by dev-finall/terraform/global"
  default     = "/upskill-devops/deployments"
}
