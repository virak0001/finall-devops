# ─── Cluster ─────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version the control plane runs"
  value       = module.eks.cluster_version
}

output "kubeconfig_command" {
  description = "Writes a kubeconfig context for this cluster — what `make kubeconfig` runs"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}

output "pod_identities" {
  description = "Controllers that have an AWS role — install each under exactly this namespace and service account"
  value       = module.eks.pod_identities
}

output "node_role_arn" {
  description = "IAM role the nodes run as"
  value       = module.eks.node_role_arn
}

output "cluster_log_group" {
  description = "CloudWatch log group with the control-plane and audit logs"
  value       = module.eks.log_group_name
}

# ─── Network ─────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC the cluster runs in — the load balancer controller needs it as --set vpcId"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets holding the nodes"
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnets the ALB is placed in (found by tag, listed for reference)"
  value       = module.network.public_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Cluster egress IPs — allowlist these on third-party services"
  value       = module.network.nat_gateway_public_ips
}

# ─── Registry ────────────────────────────────────────────────────────────────

output "ecr_registry_url" {
  description = "Registry host — the repositories themselves are global/'s"
  value       = local.ecr_registry_url
}

output "ecr_image_prefix" {
  description = "What every image name is prefixed with — registry host plus the repository prefix"

  # This is the value Helm needs, not ecr_registry_url. Repositories are named
  # <project>/<service>, so the host alone would resolve to a repository that
  # does not exist and every pod would sit in ImagePullBackOff.
  value = local.ecr_image_prefix
}

# ─── DNS and HTTPS ───────────────────────────────────────────────────────────

output "site_url" {
  description = "Where this workspace answers once external-dns has written the record. Null without a domain — then `kubectl get ingress` shows the ALB hostname."
  value       = local.site_url
}

output "site_hostnames" {
  description = "Hostnames on the certificate (the wildcard aside)"
  value       = local.site_hostnames
}

output "certificate_arn" {
  description = "ACM certificate for the site — the Ingress may name it with alb.ingress.kubernetes.io/certificate-arn"
  value       = local.dns_enabled ? aws_acm_certificate_validation.site[0].certificate_arn : null
}

output "route53_zone_id" {
  description = "Hosted zone external-dns writes into — its --zone-id-filter"
  value       = var.dns_zone_name != "" ? data.aws_route53_zone.this[0].zone_id : null
}

# ─── Secrets ─────────────────────────────────────────────────────────────────

output "team_secrets" {
  description = "Secrets Manager secret per team — `make secret-push` in the cluster project writes the value"
  value       = { for t, s in aws_secretsmanager_secret.team : t => s.name }
}

# ─── Handover ────────────────────────────────────────────────────────────────

output "platform_ssm_path" {
  description = "Where the cluster project reads every fact above from — PLATFORM_SSM_PREFIX=<prefix>"
  value       = "${var.platform_ssm_prefix}/${local.environment}/"
}

output "environment" {
  description = "Which environment this state holds — always the workspace name"
  value       = local.environment
}

output "waf_acl_arn" {
  description = "WAF web ACL for this environment's ALB, or null with waf_enabled = false"
  value       = var.waf_enabled ? module.waf[0].web_acl_arn : null
}

output "dashboard_name" {
  description = "CloudWatch dashboard for this environment (CloudWatch → Dashboards)"
  value       = var.enable_monitoring ? module.monitoring[0].dashboard_name : null
}

output "alb_logs_bucket" {
  description = "S3 bucket with the ALB's access logs"
  value       = var.enable_monitoring && var.alb_access_logs ? module.monitoring[0].alb_logs_bucket : null
}
