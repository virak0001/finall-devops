variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, uat, prod — or global for the registry)"
}

variable "repository_prefix" {
  type        = string
  description = "Namespace prefixed to every repository name, e.g. <prefix>/api"
}

variable "repositories" {
  type        = list(string)
  description = "Service names to create repositories for"
  default     = []
}

variable "image_tag_mutability" {
  type        = string
  description = "IMMUTABLE stops a tag being repointed after it ships"
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  type        = bool
  description = "Run the ECR vulnerability scan on every push"
  default     = true
}

variable "untagged_expiry_days" {
  type        = number
  description = "Days before untagged images are expired"
  default     = 7
}

variable "keep_by_tag_prefix" {
  type = list(object({
    prefix = string
    keep   = number
  }))
  description = "Images kept per tag prefix, most precious first — an image matched by an earlier entry is never expired by a later one"
  default     = []

  validation {
    condition     = alltrue([for k in var.keep_by_tag_prefix : k.prefix != "" && k.keep >= 1])
    error_message = "Each entry needs a non-empty prefix and keep >= 1."
  }
}

variable "keep_any_images" {
  type        = number
  description = "Number of images of any other tag to keep"
  default     = 10
}

variable "pull_principal_arns" {
  type        = list(string)
  description = "IAM principals granted pull access via the repository policy (the node role)"
  default     = []
}

variable "create_push_policy" {
  type        = bool
  description = "Create a managed policy granting push access, for the CI role"
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key for image encryption. Null uses AES256 with the AWS-managed key."
  default     = null
}

variable "force_delete" {
  type        = bool
  description = "Allow destroying repositories that still contain images"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged into every resource"
  default     = {}
}
