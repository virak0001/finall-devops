output "web_acl_arn" {
  description = "ARN of the web ACL — what the Load Balancer Controller's wafv2-acl-arn annotation takes"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_name" {
  description = "Name of the web ACL, as the WAF console lists it"
  value       = aws_wafv2_web_acl.this.name
}

output "rate_limit_exempt_ip_set_arn" {
  description = "ARN of the IP set the rate limit never counts"
  value       = aws_wafv2_ip_set.rate_limit_exempt.arn
}

output "log_group_name" {
  description = "CloudWatch log group with the request logs, or null with enable_logging = false"
  value       = var.enable_logging ? aws_cloudwatch_log_group.waf[0].name : null
}
