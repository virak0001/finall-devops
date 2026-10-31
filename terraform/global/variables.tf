variable "project_name" {
  type        = string
  description = "Repository prefix — repositories are <project>/<service>. Must match project_name in env/*.tfvars."
  default     = "upskill-devops"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "aws_account_id" {
  type        = string
  description = "The account the registry belongs to; plans refuse any other"
  default     = "570417737010"
}

variable "services" {
  type        = list(string)
  description = <<-DESC
    Service names that each get an ECR repository (named <project>/<service>).

    The same names Helm deploys under in the cluster project
    (helm/values/<group>/services.yaml). That repo may be on another machine,
    so the list is kept here and the two are matched by hand:

      a name here with no Helm entry  → a harmless empty repository
      a Helm service missing here     → nowhere to push, fails on first push

    Renaming one orphans the old repository: ECR carries prevent_destroy, so
    the plan refuses until you reconcile it.
  DESC
  default     = ["auth-api", "core-api", "client-side"]

  validation {
    condition     = alltrue([for n in var.services : can(regex("^[a-z][a-z0-9-]*$", n))])
    error_message = "Service names: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "adopt_existing_repositories" {
  type        = list(string)
  description = "Services whose repository already exists in AWS and should be imported, not created. Empty it once imported."
  default     = ["auth-api", "core-api", "client-side"]
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into every resource"
  default     = {}
}

variable "alert_email" {
  type        = string
  description = "Where deployment-failure alarms are emailed. AWS sends a confirmation link first. Null: no email, the alarm still fires."
  default     = null
}
