output "dashboard_name" {
  description = "CloudWatch dashboard for this environment"
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "alb_logs_bucket" {
  description = "S3 bucket for ALB access logs, or null with alb_access_logs = false"
  value       = var.alb_access_logs ? aws_s3_bucket.alb_logs[0].bucket : null
}

output "alarm_names" {
  description = "Every alarm this module created"
  value = concat(
    [for a in aws_cloudwatch_metric_alarm.uptime : a.alarm_name],
    aws_cloudwatch_metric_alarm.node_cpu[*].alarm_name,
    aws_cloudwatch_metric_alarm.node_memory[*].alarm_name,
    aws_cloudwatch_metric_alarm.node_failed[*].alarm_name,
    aws_cloudwatch_metric_alarm.waf_blocked[*].alarm_name,
  )
}
