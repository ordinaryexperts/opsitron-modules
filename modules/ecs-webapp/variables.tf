# =============================================================================
# Required
# =============================================================================

variable "name" {
  description = "Application name used for resource naming (max 20 chars to stay within AWS naming limits)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name))
    error_message = "Name must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }

  validation {
    condition     = length(var.name) <= 20
    error_message = "Name must be 20 characters or fewer to stay within AWS resource naming limits (ALB: 32 chars)."
  }
}

variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB (minimum 2, in different AZs)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets are required for the ALB."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least 1 private subnet is required for ECS tasks."
  }
}

variable "ecr_repository_url" {
  description = "ECR repository URL (without tag)"
  type        = string
}

variable "domain_name" {
  description = "Base domain name (e.g., example.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS records"
  type        = string
}

# =============================================================================
# ECS Configuration
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., dev1, stage1, prod1)"
  type        = string
  default     = "dev"
}

variable "subdomain" {
  description = "Subdomain prefix (empty string uses bare domain)"
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check endpoint path"
  type        = string
  default     = "/up"
}

variable "task_cpu" {
  description = "CPU units for the app task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Memory (MiB) for the app task"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of app tasks"
  type        = number
  default     = 1
}

variable "initial_image_tag" {
  description = "Initial container image tag (managed by CI/CD after first deploy)"
  type        = string
  default     = "latest"
}

variable "container_command" {
  description = "Override container command (null uses Dockerfile CMD)"
  type        = list(string)
  default     = null
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for interactive debugging"
  type        = bool
  default     = true
}

variable "environment_variables" {
  description = "Environment variables to pass to the container (merged with computed infra vars)"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets to pass to the container as map of name to SSM/SecretsManager ARN"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Auto-Scaling
# =============================================================================

variable "min_capacity" {
  description = "Minimum number of app tasks"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of app tasks"
  type        = number
  default     = 10
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto-scaling"
  type        = number
  default     = 80
}

# =============================================================================
# Feature Flags
# =============================================================================

variable "enable_rds" {
  description = "Create Aurora Serverless v2 PostgreSQL database"
  type        = bool
  default     = true
}

variable "enable_redis" {
  description = "Create ElastiCache Redis cluster"
  type        = bool
  default     = false
}

variable "enable_s3" {
  description = "Create S3 storage bucket"
  type        = bool
  default     = false
}

variable "enable_worker" {
  description = "Create a worker service (same image, different command)"
  type        = bool
  default     = false
}

variable "enable_ses" {
  description = "Create SES domain identity for sending email"
  type        = bool
  default     = false
}

# =============================================================================
# RDS Configuration (when enable_rds = true)
# =============================================================================

variable "database_subnet_ids" {
  description = "Subnet IDs for the database (required when enable_rds = true)"
  type        = list(string)
  default     = []
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "app"
}

variable "database_username" {
  description = "Master username for the database"
  type        = string
  default     = "app"
}

variable "postgres_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "17.4"
}

variable "aurora_serverless_min_capacity" {
  description = "Minimum ACU capacity for Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "aurora_serverless_max_capacity" {
  description = "Maximum ACU capacity for Aurora Serverless v2"
  type        = number
  default     = 4
}

variable "instance_count" {
  description = "Number of Aurora cluster instances"
  type        = number
  default     = 1
}

# =============================================================================
# Redis Configuration (when enable_redis = true)
# =============================================================================

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 1
}

# =============================================================================
# Worker Configuration (when enable_worker = true)
# =============================================================================

variable "worker_command" {
  description = "Command for the worker container"
  type        = list(string)
  default     = null
}

variable "worker_task_cpu" {
  description = "CPU units for the worker task"
  type        = number
  default     = 256
}

variable "worker_task_memory" {
  description = "Memory (MiB) for the worker task"
  type        = number
  default     = 512
}

variable "worker_desired_count" {
  description = "Desired number of worker tasks"
  type        = number
  default     = 1
}

# =============================================================================
# Other
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ssl_policy" {
  description = "SSL policy for the HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection (auto-enabled for prod environments regardless of this setting)"
  type        = bool
  default     = false
}
