variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, uat, prod)"
}

variable "name_suffix" {
  type        = string
  description = "What the ACL protects, appended to <project>-<env>- in its name"
  default     = "alb"
}

variable "scope" {
  type        = string
  description = "REGIONAL for an ALB or API Gateway; CLOUDFRONT for a distribution (create it in us-east-1)"
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "Must be REGIONAL or CLOUDFRONT."
  }
}

variable "rate_limit" {
  type        = number
  description = "Requests one IP may send in 5 minutes before it is blocked"
  default     = 1000

  validation {
    condition     = var.rate_limit >= 100 && var.rate_limit <= 2000000000
    error_message = "Between 100 and 2,000,000,000 requests per 5 minutes."
  }
}

variable "rate_limit_exempt_cidrs" {
  type        = list(string)
  description = "IPv4 CIDRs the rate limit never counts — the admin IPs, so a load test is not blocked. The other rules still apply to them."
  default     = []
}

variable "count_only_common_rules" {
  type        = list(string)
  description = "Rules in AWSManagedRulesCommonRuleSet that only COUNT instead of blocking — for known false positives"
  default     = []
}

variable "enable_logging" {
  type        = bool
  description = "Write every request the ACL sees to CloudWatch Logs (aws-waf-logs-<name>)"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Days to keep the WAF request logs"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into every resource"
  default     = {}
}
