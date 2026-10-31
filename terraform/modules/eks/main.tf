# EKS module — the managed Kubernetes control plane, one managed node group,
# the core add-ons, and the IAM every in-cluster controller assumes.
#
#   main.tf          control plane, secrets encryption, audit logs, access
#   nodes.tf         node IAM role, launch template, managed node group
#   addons.tf        vpc-cni, kube-proxy, coredns, EBS CSI, metrics-server …
#   pod-identity.tf  IAM roles bound to Kubernetes service accounts
#
# AWS runs the control plane — apiserver, etcd, scheduler — across three AZs.
# There is no control-plane instance to size, patch or keep a quorum of, which
# is the whole reason this replaced Kubespray (see docs/eks.md).

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# An assumed-role session ARN (arn:aws:sts::…:assumed-role/Name/session) is not
# a principal EKS accepts. The session context resolves it back to the role.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# ─── Cluster IAM ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── Secrets encryption ──────────────────────────────────────────────────────
# Kubernetes Secrets are only base64 in etcd. EKS encrypts etcd's disk anyway;
# this adds envelope encryption on top, so a Secret read straight out of etcd
# is ciphertext without this key. $1/month per key.
#
# The key cannot be removed from a cluster once added, and deleting the key
# makes every Secret in the cluster unreadable. The 7-day deletion window is
# the shortest AWS allows — the chance to cancel a `destroy` you regret.

resource "aws_kms_key" "secrets" {
  description             = "${var.cluster_name} Kubernetes Secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = local.common_tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.cluster_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_iam_role_policy" "cluster_kms" {
  name = "${var.cluster_name}-secrets-kms"
  role = aws_iam_role.cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:ListGrants", "kms:DescribeKey"]
      Resource = aws_kms_key.secrets.arn
    }]
  })
}

# ─── Control-plane logs ──────────────────────────────────────────────────────
# Created here, before the cluster, because EKS otherwise creates this exact
# group itself with retention "never expire" — and Terraform then fails the
# next apply on a group that already exists.

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ─── Cluster ─────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = var.cluster_log_types

  # EKS would otherwise install unmanaged copies of vpc-cni, kube-proxy and
  # coredns that nothing here tracks. addons.tf installs managed ones instead.
  # Changing this after creation replaces the cluster.
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids = var.private_subnet_ids

    # Private: nodes and pods reach the API without leaving the VPC.
    # Public, allowlisted: kubectl from a laptop, no bastion or SSH tunnel.
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.api_allowed_cidrs
  }

  access_config {
    # Access entries only. The aws-auth ConfigMap is how EKS used to map IAM to
    # Kubernetes, and one bad edit to it locks everyone out of the cluster.
    authentication_mode = "API"

    # The identity running the apply that creates the cluster becomes admin.
    # Whatever that identity is — IAM user, assumed role — EKS resolves it
    # itself, which is more reliable than predicting the ARN here. Everyone
    # else goes through admin_principal_arns below.
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
  }

  # STANDARD, not the default EXTENDED. A version past its 14 months of
  # standard support otherwise slides silently into extended support, which
  # bills $0.60/hour for the control plane instead of $0.10 — about $365 more a
  # month, per cluster, with no warning. STANDARD auto-upgrades instead.
  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ─── Access entries ──────────────────────────────────────────────────────────

locals {
  # EKS already made the creator admin; a second entry for the same ARN fails
  # with ResourceInUseException.
  admin_principal_arns = toset([
    for arn in var.admin_principal_arns : arn
    if arn != data.aws_iam_session_context.current.issuer_arn
  ])

  team_principals = merge([
    for team, t in var.team_access : {
      for arn in t.principal_arns : arn => {
        team          = team
        namespaces    = t.namespaces
        access_policy = t.access_policy
      }
    }
  ]...)

  access_policy_prefix = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy"
}

resource "aws_eks_access_entry" "admin" {
  for_each = local.admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = local.admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "${local.access_policy_prefix}/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# The team's identity reaches its own namespaces and nothing else. The
# kubernetes_groups give the cluster project a group name to hang finer RBAC
# on, if a team ever needs less than the access policy grants.
resource "aws_eks_access_entry" "team" {
  for_each = local.team_principals

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.key
  type              = "STANDARD"
  kubernetes_groups = ["team:${each.value.team}"]

  tags = merge(local.common_tags, { Team = each.value.team })
}

resource "aws_eks_access_policy_association" "team" {
  for_each = local.team_principals

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.key
  policy_arn    = "${local.access_policy_prefix}/${each.value.access_policy}"

  access_scope {
    type       = "namespace"
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.team]
}
