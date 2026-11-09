output "trail_arn" {
  description = "The CloudTrail trail"
  value       = aws_cloudtrail.this.arn
}

output "trail_bucket" {
  description = "S3 bucket holding the trail (AWSLogs/<account>/CloudTrail/…)"
  value       = aws_s3_bucket.trail.bucket
}

output "trail_log_group" {
  description = "CloudWatch log group with the searchable copy"
  value       = aws_cloudwatch_log_group.trail.name
}

output "security_alarm_names" {
  description = "The security alarms"
  value       = [for a in aws_cloudwatch_metric_alarm.security : a.alarm_name]
}
