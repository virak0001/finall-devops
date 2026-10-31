# EKS add-ons — cluster components AWS ships, versions and patches.
#
# No addon_version anywhere. EKS then installs the default version for the
# cluster's Kubernetes version, and Terraform reads back whatever that was
# instead of planning a change every time AWS publishes a newer build. Pin one
# by adding addon_version when an upgrade needs to be deliberate.
#
# OVERWRITE on both create and update: an add-on's config is Terraform's, and a
# field hand-edited in the cluster is put back on the next apply rather than
# blocking it as a conflict.

# ─── Before the nodes ────────────────────────────────────────────────────────
# What a node needs to go Ready. These install as soon as the control plane is
# up; their pods sit Pending until nodes join, which is fine — the node group
# depends on these resources existing, not on their pods running.

resource "aws_eks_addon" "before_compute" {
  for_each = {
    # Pod networking: every pod gets a real VPC address. enableNetworkPolicy
    # makes the CNI enforce Kubernetes NetworkPolicy, which is what keeps one
    # team's namespace from reaching another's.
    "vpc-cni" = jsonencode({ enableNetworkPolicy = "true" })

    "kube-proxy" = null

    # The node agent every pod identity in pod-identity.tf is served through.
    "eks-pod-identity-agent" = null
  }

  cluster_name         = aws_eks_cluster.this.name
  addon_name           = each.key
  configuration_values = each.value

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

# ─── After the nodes ─────────────────────────────────────────────────────────
# These run Deployments, so they need somewhere to schedule. Created before the
# node group, they wait Degraded for their full timeout and fail the apply.

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags       = local.common_tags
  depends_on = [aws_eks_node_group.default]
}

# PersistentVolumeClaims backed by EBS. The add-on creates the pod identity
# association itself, for the controller's own service account.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags       = local.common_tags
  depends_on = [aws_eks_node_group.default]
}

# The resource-metrics API. The Horizontal Pod Autoscaler reads CPU and memory
# from here; without it every HPA reports <unknown> and never scales.
resource "aws_eks_addon" "metrics_server" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "metrics-server"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags       = local.common_tags
  depends_on = [aws_eks_node_group.default]
}

# Container Insights: node, pod and container metrics, and Fluent Bit shipping
# every container's stdout to /aws/containerinsights/<cluster>/application.
resource "aws_eks_addon" "cloudwatch" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "amazon-cloudwatch-observability"

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch[0].arn
    service_account = "cloudwatch-agent"
  }

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags       = local.common_tags
  depends_on = [aws_eks_node_group.default]
}
