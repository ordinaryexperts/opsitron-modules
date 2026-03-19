# LZA Foundation Module - Variables

# Prerequisites
variable "github_token_secret_name" {
  description = "Name of the Secrets Manager secret containing the GitHub PAT for LZA pipeline access"
  type        = string
  default     = "accelerator/github-token"
}

# Required Variables
variable "management_account_email" {
  description = "Email address for the management account root user"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.management_account_email))
    error_message = "Must be a valid email address."
  }
}

variable "log_archive_account_email" {
  description = "Email address for the log archive account root user"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.log_archive_account_email))
    error_message = "Must be a valid email address."
  }
}

variable "audit_account_email" {
  description = "Email address for the audit account root user"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.audit_account_email))
    error_message = "Must be a valid email address."
  }
}

# Optional Variables with Defaults
variable "accelerator_prefix" {
  description = "Prefix for all LZA resources (must be lowercase)"
  type        = string
  default     = "lza"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.accelerator_prefix))
    error_message = "Prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "control_tower_enabled" {
  description = "Set to true to use Control Tower with LZA (recommended). LZA will integrate with existing Control Tower or set it up if needed. Set to false for Organizations-only mode (you must first set up mandatory accounts: LogArchive, Audit)."
  type        = bool
  default     = true
}


variable "lza_source_location" {
  description = "Where to host the LZA source code (github or codecommit)"
  type        = string
  default     = "github"

  validation {
    condition     = contains(["github", "codecommit"], var.lza_source_location)
    error_message = "Must be one of: github, codecommit"
  }
}

variable "lza_source_owner" {
  description = "Owner of the LZA source code repository (GitHub only)"
  type        = string
  default     = "awslabs"
}

variable "lza_source_repo_name" {
  description = "Name of the LZA source code repository"
  type        = string
  default     = "landing-zone-accelerator-on-aws"
}

variable "lza_source_branch" {
  description = "Branch name for the LZA source code repository"
  type        = string
  default     = "release/v1.14.2"
}

variable "enable_approval_stage" {
  description = "Enable manual approval stage in CodePipeline (requires approval_stage_notify_email if true)"
  type        = bool
  default     = false
}

variable "approval_stage_notify_email" {
  description = "Email to notify for pipeline approvals"
  type        = string
  default     = ""
}


variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}


# Configuration repository is always S3. The GitHub workflow uploads config files
# from the client's lza-config repository to S3, then triggers the pipeline.
# This enables deploy-before-merge workflows where feature branches can be deployed.

variable "enable_diagnostics_pack" {
  description = "Enable diagnostics pack for root cause analysis"
  type        = bool
  default     = true
}

variable "lambda_concurrency_limit" {
  description = "Set ACCELERATOR_LAMBDA_CONCURRENCY_LIMIT on the Toolkit CodeBuild project. This bypasses Lambda concurrent execution validation that fails on new AWS accounts. Set to 0 to disable. See: https://github.com/awslabs/landing-zone-accelerator-on-aws/issues/984"
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_concurrency_limit >= 0
    error_message = "Lambda concurrency limit must be 0 or greater."
  }
}
