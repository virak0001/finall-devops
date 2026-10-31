variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
}

variable "environment" {
  type        = string
  description = "Environment name — the Terraform workspace"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name. Also the prefix of every IAM role this module creates."
}

variable "kubernetes_version" {
  type        = string
  description = "EKS minor version, e.g. 1.36"
}

variable "vpc_id" {
  type        = string
  description = "VPC the cluster runs in"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = <<-DESC
    Private subnets for the control-plane ENIs and the nodes.

    At least two, in different availability zones — EKS rejects a single AZ.
    Public subnets are not passed in at all: the load balancer controller finds
    them by their kubernetes.io/role/elb tag (see modules/network).
  DESC

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

# ─── API access ──────────────────────────────────────────────────────────────

variable "api_allowed_cidrs" {
  type        = list(string)
  description = <<-DESC
    CIDRs allowed to reach the public Kubernetes API endpoint.

    Nodes and pods use the private endpoint and are not affected. Anyone else
    — kubectl on a laptop — must be in here. A request from outside the list
    is dropped, not refused, so kubectl hangs and then times out.
  DESC

  validation {
    condition     = length(var.api_allowed_cidrs) > 0
    error_message = "Name at least one CIDR, or nobody outside the VPC can run kubectl."
  }

  validation {
    condition     = !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Refusing to open the Kubernetes API to the whole internet. Use a specific CIDR."
  }
}

variable "admin_principal_arns" {
  type        = list(string)
  description = <<-DESC
    IAM users or roles that get cluster-admin, in addition to whoever runs the
    apply that creates the cluster (EKS grants that identity admin itself).
  DESC
  default     = []
}

variable "team_access" {
  type = map(object({
    principal_arns = list(string)
    namespaces     = list(string)
    access_policy  = optional(string, "AmazonEKSEditPolicy")
  }))
  description = <<-DESC
    Per-team access, scoped to that team's namespaces.

      team_access = {
        team-a = {
          principal_arns = ["arn:aws:iam::123456789012:role/team-a-dev"]
          namespaces     = ["team-a-uat", "team-a-prod"]
        }
      }

    access_policy is an EKS access policy name: AmazonEKSViewPolicy,
    AmazonEKSEditPolicy (the default) or AmazonEKSAdminPolicy. The namespaces
    themselves, and any finer-grained RBAC inside them, belong to the cluster
    project — this only decides which IAM identity reaches which namespace.
  DESC
  default     = {}

  validation {
    condition = alltrue([
      for t in values(var.team_access) :
      contains(["AmazonEKSViewPolicy", "AmazonEKSEditPolicy", "AmazonEKSAdminPolicy"], t.access_policy)
    ])
    error_message = "access_policy must be AmazonEKSViewPolicy, AmazonEKSEditPolicy or AmazonEKSAdminPolicy."
  }

  # One access entry per principal, so a principal in two teams would be two
  # entries for the same ARN — which EKS rejects at apply, after the cluster is
  # already half-built.
  validation {
    condition = (
      length(flatten([for t in values(var.team_access) : t.principal_arns])) ==
      length(distinct(flatten([for t in values(var.team_access) : t.principal_arns])))
    )
    error_message = "A principal may belong to one team only. Give it a role per team instead."
  }
}

# ─── Nodes ───────────────────────────────────────────────────────────────────

variable "node_instance_types" {
  type        = list(string)
  description = <<-DESC
    Instance types for the managed node group. More than one only matters for
    SPOT, where it widens the pools capacity can come from.

    Pod density is set by the instance's network interfaces, not its memory —
    the VPC CNI gives every pod a real VPC address. t3.medium fits 17 pods,
    t3.large and c7i-flex.large 35 and 29.
  DESC
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  type        = string
  description = "ON_DEMAND, or SPOT for roughly a third of the price and nodes that can vanish on two minutes' notice"
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "Must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  type        = number
  description = "Smallest the node group may shrink to"
  default     = 1
}

variable "node_desired_size" {
  type        = number
  description = <<-DESC
    Nodes at creation. Ignored after that — once an autoscaler owns the count,
    Terraform resetting it on every apply would fight it.
  DESC
  default     = 2
}

variable "node_max_size" {
  type        = number
  description = "Largest the node group may grow to"
  default     = 3
}

variable "node_disk_size" {
  type        = number
  description = "Root volume in GB. Image layers live here."
  default     = 50
}

# ─── Observability ───────────────────────────────────────────────────────────

variable "cluster_log_types" {
  type        = list(string)
  description = <<-DESC
    Control-plane logs shipped to CloudWatch. "audit" is the record of who did
    what through the Kubernetes API — every kubectl, every Argo CD sync.
  DESC
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch retention for the control-plane logs"
  default     = 30
}

variable "enable_container_insights" {
  type        = bool
  description = <<-DESC
    Install the amazon-cloudwatch-observability add-on: Container Insights
    metrics plus Fluent Bit shipping every pod's stdout to CloudWatch Logs.
    Billed per metric and per GB of logs ingested, so off by default.
  DESC
  default     = false
}

# ─── Pod identities ──────────────────────────────────────────────────────────

variable "route53_zone_arn" {
  type        = string
  description = "Hosted zone external-dns may write records into. Null skips the external-dns role."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into every resource"
  default     = {}
}
