variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
}

variable "alarm_topic_arn" {
  type        = string
  description = "SNS topic the security alarms notify. Null: they still change state, but tell no one"
  default     = null
}

variable "trail_retention_days" {
  type        = number
  description = "Days to keep the trail in S3"
  default     = 365
}

variable "cloudwatch_retention_days" {
  type        = number
  description = "Days to keep the searchable copy in CloudWatch Logs"
  default     = 90
}

variable "denied_calls_threshold" {
  type        = number
  description = "Denied API calls in 5 minutes that alarm — some are normal (tools probing optional permissions)"
  default     = 10
}

variable "force_destroy" {
  type        = bool
  description = "Let `terraform destroy` delete the trail bucket with its logs in it. Off: an audit log should outlive a mistake"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into every resource"
  default     = {}
}
