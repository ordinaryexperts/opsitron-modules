# =============================================================================
# Resource Selection
# =============================================================================

variable "create_ecr_repository" {
  description = "Whether to create an ECR repository"
  type        = bool
  default     = true
}

variable "create_artifact_bucket" {
  description = "Whether to create an S3 artifact bucket"
  type        = bool
  default     = true
}

# =============================================================================
# Common
# =============================================================================

variable "organization_path" {
  description = "AWS Organizations path for cross-account access policies (e.g., o-abc123/r-root/ou-workloads)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# ECR Repositories (one per application)
# =============================================================================

variable "ecr_repositories" {
  description = "Map of application slug to ECR repository config. One repo is created per entry, named {namespace}/{slug}. Use get_shared_services_config MCP tool to get the current list."
  type = map(object({
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    encryption_type      = optional(string, "AES256")
    kms_key_arn          = optional(string, null)
    max_image_count      = optional(number, 30)
  }))
  default = {}
}

variable "ecr_namespace" {
  description = "Namespace prefix for ECR repository names (e.g., 'acme-corp'). Repos are named {namespace}/{slug}."
  type        = string
  default     = null
}

variable "ecr_untagged_image_expiry_days" {
  description = "Days to keep untagged images before deletion"
  type        = number
  default     = 30
}

# =============================================================================
# Artifact Bucket
# =============================================================================

variable "artifact_bucket_name" {
  description = "Exact name of the S3 bucket for artifacts. If set, bucket_prefix is ignored. Use for existing buckets."
  type        = string
  default     = null

  validation {
    condition     = var.artifact_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.artifact_bucket_name))
    error_message = "Bucket name must be lowercase, start/end with letter or number, and contain only letters, numbers, hyphens, and periods."
  }
}

variable "artifact_bucket_prefix" {
  description = "Prefix for auto-generated S3 bucket name. Used when artifact_bucket_name is null. AWS appends a random suffix for uniqueness."
  type        = string
  default     = "artifacts-"
}

variable "artifact_enable_versioning" {
  description = "Enable S3 versioning for artifact history"
  type        = bool
  default     = true
}

variable "artifact_enable_lifecycle_policy" {
  description = "Enable lifecycle policy to clean up old artifact versions"
  type        = bool
  default     = true
}

variable "artifact_noncurrent_version_expiry_days" {
  description = "Days before noncurrent versions are deleted"
  type        = number
  default     = 90
}

variable "artifact_abort_incomplete_multipart_days" {
  description = "Days before incomplete multipart uploads are aborted"
  type        = number
  default     = 7
}

variable "artifact_force_destroy" {
  description = "Allow bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}
