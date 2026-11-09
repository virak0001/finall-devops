variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, uat, prod)"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name — the ClusterName dimension of the Container Insights metrics"
}

variable "alb_name" {
  type        = string
  description = "Name the cluster project gives the shared ALB; the dashboard's ALB graphs search for it"
}

variable "alarm_topic_arn" {
  type        = string
  description = "SNS topic every alarm notifies. Null: alarms still change state and show on the dashboard, but tell no one"
  default     = null
}

variable "uptime_checks" {
  type = map(object({
    fqdn = string
    path = string
  }))
  description = "Public HTTPS URLs to health-check from outside, keyed by a short name used in the alarm name"
  default     = {}
}

variable "container_insights_enabled" {
  type        = bool
  description = "Whether the cluster runs Container Insights — the node alarms and graphs need its metrics"
  default     = false
}

variable "waf_enabled" {
  type        = bool
  description = "Whether a WAF web ACL fronts the ALB — adds its graph and the blocked-requests alarm"
  default     = false
}

variable "waf_web_acl_name" {
  type        = string
  description = "Name of that web ACL (the WebACL dimension)"
  default     = ""
}

variable "alb_access_logs" {
  type        = bool
  description = "Create the S3 bucket the ALB writes its access logs to"
  default     = true
}

variable "alb_log_prefix" {
  type        = string
  description = "Prefix inside the bucket; the cluster project's annotation must use the same"
  default     = "alb"
}

variable "log_retention_days" {
  type        = number
  description = "Days to keep ALB access logs"
  default     = 30
}

variable "cpu_alarm_threshold" {
  type        = number
  description = "Average node CPU % that alarms after 10 minutes"
  default     = 80
}

variable "memory_alarm_threshold" {
  type        = number
  description = "Average node memory % that alarms after 10 minutes"
  default     = 80
}

variable "waf_blocked_threshold" {
  type        = number
  description = "Requests blocked in 5 minutes that alarms"
  default     = 100
}

variable "extra_alarm_arns" {
  type        = list(string)
  description = "Other alarms to show in the dashboard's alarm row (e.g. the global deployment-failed alarm)"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into every resource"
  default     = {}
}
