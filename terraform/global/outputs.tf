output "ecr_registry_url" {
  description = "Registry host to docker login against"
  value       = module.registry.registry_url
}

output "ecr_image_prefix" {
  description = "Registry host plus the repository prefix — what Helm's global.imageRegistry needs"
  value       = module.registry.registry_url == null ? null : "${module.registry.registry_url}/${var.project_name}"
}

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = module.registry.repository_urls
}

output "ecr_push_policy_arn" {
  description = "Managed policy granting push to these repositories — attach it to the Jenkins role"
  value       = module.registry.push_policy_arn
}

output "ecr_login_command" {
  description = "Docker login command for the registry"
  value       = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "deployments_log_group" {
  description = "Where every deployment is recorded — the pipelines write here"
  value       = aws_cloudwatch_log_group.deployments.name
}

output "alerts_topic_arn" {
  description = "SNS topic every platform alarm notifies"
  value       = aws_sns_topic.alerts.arn
}
