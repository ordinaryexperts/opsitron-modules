variable "name" {
  description = "Name for the website resources (used in bucket names, SSM parameters, etc.)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "Name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev1, stage1, prod1)"
  type        = string
}

variable "domain" {
  description = "Domain name for the website (e.g., www.example.com)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. Must be in us-east-1 for CloudFront."
  type        = string
}

variable "artifact_bucket_arn" {
  description = "ARN of the S3 bucket containing build artifacts in SharedServices account"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Optional features

variable "waf_acl_arn" {
  description = "WAF Web ACL ARN to attach to CloudFront distribution"
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFront price class. Options: PriceClass_100 (US/EU), PriceClass_200 (US/EU/Asia), PriceClass_All"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "Price class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "custom_error_responses" {
  description = "Custom error response configurations. Default returns 404 for missing pages. For SPAs, override with response_code=200 and response_page_path='/index.html'."
  type = list(object({
    error_code         = number
    response_code      = number
    response_page_path = string
  }))
  default = []
}

variable "default_root_object" {
  description = "Default root object (index file)"
  type        = string
  default     = "index.html"
}

variable "enable_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = false
}

variable "logging_bucket" {
  description = "S3 bucket for CloudFront access logs (required if enable_logging is true)"
  type        = string
  default     = null
}

variable "logging_prefix" {
  description = "Prefix for CloudFront access logs"
  type        = string
  default     = "cloudfront/"
}

variable "minimum_protocol_version" {
  description = "Minimum TLS protocol version for CloudFront"
  type        = string
  default     = "TLSv1.2_2021"
}

variable "domain_aliases" {
  description = "Custom domain aliases for CloudFront. When set, replaces the default domain as CF aliases."
  type        = list(string)
  default     = []
}

variable "domain_alias_certificate_arns" {
  description = "ACM certificate ARNs for domain aliases. First cert used as viewer certificate when aliases present."
  type        = list(string)
  default     = []
}

variable "force_destroy" {
  description = "Allow the S3 bucket to be destroyed even when it contains objects."
  type        = bool
  default     = false
}

variable "bucket_name" {
  description = "Explicit S3 bucket name. When set, uses this instead of generating a name with bucket_prefix. Use for existing buckets to avoid recreation."
  type        = string
  default     = null
}
