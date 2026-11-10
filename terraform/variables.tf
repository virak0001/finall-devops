# ─── Identity ────────────────────────────────────────────────────────────────

variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging. Must match global/ — it is also the ECR repository prefix."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.project_name))
    error_message = "Use lowercase letters, digits and hyphens (2-25 chars)."
  }
}

variable "shared_project_name" {
  type        = string
  description = <<-DESC
    global/'s project_name — what the account-wide resources every environment
    shares are named after: the ECR prefix (<name>/<service>), the alerts SNS
    topic (<name>-alerts) and the deployment-failed alarm. Separate from
    project_name because an environment may be named differently (prod is
    group-3-devops) while those stay one set for the whole account.
  DESC
  default     = "upskill-devops"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name. Null falls back to <project>-<environment>."
  default     = null
}

variable "aws_account_id" {
  type        = string
  description = <<-DESC
    The AWS account this environment belongs to.

    Set it, and every plan checks the credentials in your shell actually point
    there. Leave it null and there is no check — which is how a credential
    change ends up building a second copy of an environment in the wrong
    account while the first keeps running and billing.
  DESC
  default     = null

  validation {
    condition     = var.aws_account_id == null || can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into every resource"
  default     = {}
}

# ─── Network ─────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to spread the cluster across"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "single_nat_gateway" {
  type        = bool
  description = "One shared NAT gateway instead of one per AZ (~$32/mo each)"
  default     = true
}

variable "enable_flow_logs" {
  type        = bool
  description = "Ship rejected-traffic VPC flow logs to CloudWatch"
  default     = false
}

# ─── Cluster ─────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  type        = string
  description = <<-DESC
    EKS minor version. 1.36 is in standard support until 2027-08-02.

    Upgrades go one minor at a time — 1.36 → 1.37, never 1.36 → 1.38 — and the
    control plane cannot be downgraded after the 7-day rollback window. Raise
    it one step, apply, and the node group rolls onto the matching AMI.
  DESC
  default     = "1.36"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "A minor version only, like 1.36."
  }
}

variable "api_allowed_cidrs" {
  type        = list(string)
  description = <<-DESC
    CIDRs allowed to reach the Kubernetes API from outside the VPC — your
    public egress IP as AWS sees it, not a 192.168.x address.

      make myip     WORKSPACE=<env>   does this still match?
      make myip-set WORKSPACE=<env>   rewrite it to your current one
  DESC
}

variable "admin_principal_arns" {
  type        = list(string)
  description = "IAM users or roles given cluster-admin, besides whoever created the cluster"
  default     = []
}

variable "team_access" {
  type = map(object({
    principal_arns = list(string)
    namespaces     = list(string)
    access_policy  = optional(string, "AmazonEKSEditPolicy")
  }))
  description = "Per-team IAM access scoped to that team's namespaces — see modules/eks/variables.tf"
  default     = {}
}

# ─── Nodes ───────────────────────────────────────────────────────────────────

variable "node_instance_types" {
  type        = list(string)
  description = "Instance types for the managed node group"
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  type        = string
  description = "ON_DEMAND or SPOT"
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  type        = number
  description = "Smallest the node group may shrink to"
  default     = 1
}

variable "node_desired_size" {
  type        = number
  description = "Nodes at creation; an autoscaler owns the count after that"
  default     = 2
}

variable "node_max_size" {
  type        = number
  description = "Largest the node group may grow to"
  default     = 3
}

variable "node_disk_size" {
  type        = number
  description = "Node root volume in GB"
  default     = 50
}

# ─── Observability ───────────────────────────────────────────────────────────

variable "cluster_log_types" {
  type        = list(string)
  description = "Control-plane log types sent to CloudWatch"
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch retention for control-plane logs"
  default     = 30
}

variable "enable_container_insights" {
  type        = bool
  description = "Container Insights metrics + Fluent Bit pod logs (billed per metric and per GB)"
  default     = false
}

# ─── DNS and HTTPS ───────────────────────────────────────────────────────────

variable "dns_zone_name" {
  type        = string
  description = <<-DESC
    Public hosted zone this environment's hostnames live in — "example.com".

    Empty disables DNS entirely: no certificate, no external-dns role, and
    the ALB's own hostname is the only address.

    The zone must already exist and be delegated from the registrar.
    Terraform reads it; it never creates or destroys it, so a workspace
    teardown cannot break the delegation.
  DESC
  default     = ""
}

variable "site_hostname" {
  type        = string
  description = <<-DESC
    The hostname this environment answers on, inside dns_zone_name —
    "dev.example.com", or the apex for prod.

    Terraform issues an ACM certificate for it and for *.<site_hostname>, so
    admin UIs (argocd.<site_hostname>) are covered too. The record pointing
    it at the ALB is external-dns's, made from the Ingress host.
  DESC
  default     = ""

  validation {
    condition     = var.site_hostname == "" || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.site_hostname))
    error_message = "A lowercase hostname, like dev.example.com."
  }
}

variable "site_aliases" {
  type        = list(string)
  description = "Extra hostnames on the same certificate — [\"www.example.com\"]"
  default     = []
}

# ─── Teams ───────────────────────────────────────────────────────────────────

variable "teams" {
  type        = list(string)
  description = <<-DESC
    Teams that deploy into the cluster. Each is a namespace of the same name
    and a group in the cluster project's catalogue
    (helm/values/<team>/services.yaml), and gets a Secrets Manager secret and
    a role that can read only that secret.

    Matched to the catalogue by hand, like var.services in global/.
  DESC
  default     = ["api-service", "web-service"]

  validation {
    condition     = alltrue([for t in var.teams : can(regex("^[a-z][a-z0-9-]{0,30}$", t))])
    error_message = "Team names are namespace names: lowercase letters, digits and hyphens."
  }
}

variable "secret_recovery_window_days" {
  type        = number
  description = "Days a deleted team secret can be restored. 0 deletes at once, so the environment can be rebuilt immediately."
  default     = 0

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "0, or 7 to 30 — the only values Secrets Manager accepts."
  }
}

# ─── Handover ────────────────────────────────────────────────────────────────

variable "platform_ssm_prefix" {
  type        = string
  description = <<-DESC
    SSM Parameter Store path the platform facts are published under, as
    <prefix>/<workspace>/<key>. The cluster project reads the same path with
    PLATFORM_SSM_PREFIX=<prefix>, so nothing is pasted between the two.
  DESC
  default     = "/platform"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", var.platform_ssm_prefix))
    error_message = "An absolute SSM path with no trailing slash, like /platform."
  }
}

# ─── WAF (module.waf in main.tf) ─────────────────────────────────────────────

variable "waf_enabled" {
  type        = bool
  description = "Put a WAF web ACL in front of this environment's ALB (published to SSM as waf_acl_arn)"
  default     = true
}

variable "waf_rate_limit" {
  type        = number
  description = "Requests one IP may send in 5 minutes before the WAF blocks it (api_allowed_cidrs are exempt)"
  default     = 1000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 2000000000
    error_message = "Between 100 and 2,000,000,000 requests per 5 minutes."
  }
}

# ─── Monitoring (module.monitoring in main.tf) ───────────────────────────────

variable "enable_monitoring" {
  type        = bool
  description = "Dashboard, alarms and uptime checks for this environment (modules/monitoring)"
  default     = true
}

variable "alb_access_logs" {
  type        = bool
  description = "Create an S3 bucket for the ALB's access logs and have the Ingresses turn them on (published to SSM as alb_logs_bucket)"
  default     = true
}

variable "cpu_alarm_threshold" {
  type        = number
  description = "Average node CPU % that alarms after 10 minutes (needs enable_container_insights)"
  default     = 80
}

variable "memory_alarm_threshold" {
  type        = number
  description = "Average node memory % that alarms after 10 minutes (needs enable_container_insights)"
  default     = 80
}
