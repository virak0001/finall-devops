# ─── Node IAM ────────────────────────────────────────────────────────────────
# What the EC2 instance itself may do. Kept to the four managed policies a node
# needs to join, network and pull. Anything a workload needs — the load
# balancer controller's ELB calls, EBS volumes, Route 53 — is a pod identity
# (pod-identity.tf), so it is granted to that one service account and not to
# every pod on the node.

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    # Pull only. The older AmazonEC2ContainerRegistryReadOnly also lets a node
    # list and describe every repository in the account.
    "AmazonEC2ContainerRegistryPullOnly",
    # Shell on a node without SSH, a key pair, or an open port 22.
    "AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# ─── Launch template ─────────────────────────────────────────────────────────
# Only for what the node group cannot set itself: IMDSv2, and an encrypted gp3
# root volume. No AMI and no security groups here — naming either takes them
# away from EKS, which then stops attaching the cluster security group and
# stops picking the AMI for var.kubernetes_version.

resource "aws_launch_template" "node" {
  name_prefix            = "${var.cluster_name}-node-"
  update_default_version = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only

    # 2 lets a pod reach the instance metadata service through the extra
    # network hop a container adds; 1 would block it. 1 is the tighter
    # setting — it stops any pod borrowing the node role above — but the
    # CloudWatch agent and Fluent Bit read instance metadata from inside
    # pods. Drop to 1 once nothing in the cluster needs IMDS.
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda" # the AL2023 root device

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.cluster_name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${var.cluster_name}-node" })
  }

  tags = local.common_tags
}

# ─── Managed node group ──────────────────────────────────────────────────────
# EKS owns the Auto Scaling group behind this: it drains and replaces nodes on
# an AMI or version upgrade, one at a time, without anyone running a playbook.

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  # AL2023, because EKS publishes no Amazon Linux 2 AMIs from 1.33 on.
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    "node-pool" = "default"
  }

  tags = local.common_tags

  lifecycle {
    # Cluster Autoscaler or Karpenter moves this once it is installed.
    ignore_changes = [scaling_config[0].desired_size]
  }

  # A node with no CNI never goes Ready, and the node group waits for Ready —
  # so it would sit for its full 20-minute timeout and then fail. The
  # before-compute add-ons are what give it a network to come up on.
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_compute,
  ]
}
