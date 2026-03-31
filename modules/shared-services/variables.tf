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
# ECR Repository
# =============================================================================

variable "ecr_repository_name" {
  description = "Name of the ECR repository (e.g., 123456789012-client-slug/app-name)"
  type        = string
  default     = null

  validation {
    condition     = var.ecr_repository_name == null || can(regex("^[a-z0-9][a-z0-9/_-]*$", var.ecr_repository_name))
    error_message = "Repository name must start with lowercase letter or number and contain only lowercase letters, numbers, hyphens, underscores, and forward slashes."
  }
}

variable "ecr_image_tag_mutability" {
  description = "Tag mutability setting. IMMUTABLE prevents overwriting tags."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "Image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable vulnerability scanning when images are pushed"
  type        = bool
  default     = true
}

variable "ecr_encryption_type" {
  description = "Encryption type for the repository (AES256 or KMS)"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.ecr_encryption_type)
    error_message = "Encryption type must be AES256 or KMS."
  }
}

variable "ecr_kms_key_arn" {
  description = "KMS key ARN for encryption (required if ecr_encryption_type is KMS)"
  type        = string
  default     = null
}

variable "ecr_enable_lifecycle_policy" {
  description = "Enable lifecycle policy to clean up untagged images"
  type        = bool
  default     = true
}

variable "ecr_untagged_image_expiry_days" {
  description = "Days to keep untagged images before deletion"
  type        = number
  default     = 30
}

variable "ecr_max_image_count" {
  description = "Maximum number of tagged images to keep (0 = unlimited). Ignored when application_slugs is set (per-app rules are used instead)."
  type        = number
  default     = 0
}

variable "application_slugs" {
  description = "List of application slugs sharing this ECR repo. Images are tagged with {slug}-{sha}. Generates per-app lifecycle rules keeping the latest ecr_max_images_per_app images per prefix."
  type        = list(string)
  default     = []
}

variable "ecr_max_images_per_app" {
  description = "Maximum number of tagged images to keep per application prefix (used with application_slugs). Set high enough that production images won't be expired by frequent dev pushes."
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
