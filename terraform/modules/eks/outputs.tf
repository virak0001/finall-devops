output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version the control plane runs"
  value       = aws_eks_cluster.this.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle for the API endpoint"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group EKS attaches to the control plane and every node"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "IAM role the nodes run as"
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the node IAM role, for attaching additional policies"
  value       = aws_iam_role.node.name
}

output "pod_identities" {
  description = "Service accounts that have an AWS role, and which — install each controller under exactly this namespace and name"
  value = {
    for k, v in local.pod_identities : k => {
      namespace       = v.namespace
      service_account = v.service_account
      role_arn        = aws_iam_role.pod_identity[k].arn
    }
  }
}

output "secrets_kms_key_arn" {
  description = "KMS key encrypting Kubernetes Secrets in etcd"
  value       = aws_kms_key.secrets.arn
}

output "log_group_name" {
  description = "CloudWatch log group holding the control-plane and audit logs"
  value       = aws_cloudwatch_log_group.cluster.name
}
