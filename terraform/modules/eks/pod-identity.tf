# Pod identities — IAM roles a single Kubernetes service account can assume.
#
# This is the contract with the cluster project. Terraform decides what each
# controller may do in AWS and binds it to a fixed namespace and service
# account name; the cluster project installs the controller under exactly that
# name and passes no credentials at all. The pod identity agent (addons.tf)
# hands the pod short-lived credentials for its role, and nothing else on the
# node can use them.
#
#   namespace/service account                    role
#   kube-system/aws-load-balancer-controller     <cluster>-aws-load-balancer-controller
#   kube-system/cluster-autoscaler               <cluster>-cluster-autoscaler
#   external-dns/external-dns                    <cluster>-external-dns
#   external-secrets/external-secrets            <cluster>-external-secrets
#   kube-system/ebs-csi-controller-sa            <cluster>-ebs-csi        (via the add-on)
#   amazon-cloudwatch/cloudwatch-agent           <cluster>-cloudwatch     (via the add-on)
#
# Install a controller under any other name and it runs with no AWS
# permissions — its logs show AccessDenied or "no EC2 IMDS role found".
#
# Pod Identity rather than IRSA: no OIDC provider to create, and the trust
# policy below is the same for every role instead of naming the cluster's OIDC
# issuer and the service account in each one.

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    # Only pods of THIS cluster. Without it, a pod identity association in any
    # other cluster in the account could name one of these roles.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_eks_cluster.this.arn]
    }
  }
}

# ─── Controllers the cluster project installs ────────────────────────────────

locals {
  pod_identities = merge(
    {
      aws-load-balancer-controller = {
        namespace       = "kube-system"
        service_account = "aws-load-balancer-controller"

        # The controller's own published policy, copied verbatim from
        # kubernetes-sigs/aws-load-balancer-controller at the tag in the file
        # name (docs/install/iam_policy.json). Install that chart version, or
        # a newer controller may call an API this policy predates.
        policy = file("${path.module}/policies/aws-load-balancer-controller-v3.5.0.json")
      }

      cluster-autoscaler = {
        namespace       = "kube-system"
        service_account = "cluster-autoscaler"
        policy          = data.aws_iam_policy_document.cluster_autoscaler.json
      }

      # Holds no secret itself. It only assumes the per-team roles below, so a
      # team's SecretStore can read that team's secrets and nobody else's.
      external-secrets = {
        namespace       = "external-secrets"
        service_account = "external-secrets"
        policy          = data.aws_iam_policy_document.external_secrets.json
      }
    },
    var.route53_zone_arn == null ? {} : {
      external-dns = {
        namespace       = "external-dns"
        service_account = "external-dns"
        policy          = data.aws_iam_policy_document.external_dns[0].json
      }
    },
  )
}

# Writes records in the one zone it is given, and reads enough of Route 53 to
# find it. Not ChangeResourceRecordSets on "*" — that would let it rewrite any
# domain in the account.
data "aws_iam_policy_document" "external_dns" {
  count = var.route53_zone_arn == null ? 0 : 1

  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [var.route53_zone_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResources",
    ]
    resources = ["*"]
  }
}

# Reads every Auto Scaling group, but resizes only the ones EKS tagged as this
# cluster's — a managed node group's ASG carries
# k8s.io/cluster-autoscaler/<cluster>=owned without anyone adding it. The
# actions are the autoscaler's own documented minimum for AWS.
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

# By name pattern, not by ARN, so the roles can be created after this policy
# without a dependency cycle (they trust the role this policy is on).
data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-secrets-*"]
  }
}

resource "aws_iam_role" "pod_identity" {
  for_each = local.pod_identities

  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "pod_identity" {
  for_each = local.pod_identities

  name   = each.key
  role   = aws_iam_role.pod_identity[each.key].id
  policy = each.value.policy
}

# Can exist before the namespace or service account does — EKS matches on the
# names when a pod starts, so the cluster project can install in any order.
resource "aws_eks_pod_identity_association" "this" {
  for_each = local.pod_identities

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.pod_identity[each.key].arn

  tags = local.common_tags
}

# ─── Roles the add-ons bind themselves ───────────────────────────────────────
# Same trust, but the association is made by aws_eks_addon (addons.tf), so the
# add-on and its permissions are created and removed together.

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "cloudwatch" {
  count = var.enable_container_insights ? 1 : 0

  name               = "${var.cluster_name}-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count = var.enable_container_insights ? 1 : 0

  role       = aws_iam_role.cloudwatch[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}
