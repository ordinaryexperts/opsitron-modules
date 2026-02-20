# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Locals
# =============================================================================

locals {
  name_prefix = "${var.name}-${var.environment}"
  fqdn        = var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name
  app_url     = "https://${local.fqdn}"

  # Derive postgres major version from full version for parameter group family
  postgres_major_version = regex("^(\\d+)", var.postgres_version)[0]

  is_prod = can(regex("^prod", var.environment))

  common_tags = merge(var.tags, {
    Name        = local.name_prefix
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # Computed environment variables from infrastructure resources
  infra_environment = merge(
    {
      "AWS_DEFAULT_REGION" = data.aws_region.current.id
      "AWS_ACCOUNT_ID"     = data.aws_caller_identity.current.account_id
    },
    var.enable_rds ? {
      "DATABASE_HOST"     = aws_rds_cluster.main[0].endpoint
      "DATABASE_PORT"     = tostring(aws_rds_cluster.main[0].port)
      "DATABASE_NAME"     = aws_rds_cluster.main[0].database_name
      "DATABASE_USERNAME" = aws_rds_cluster.main[0].master_username
    } : {},
    var.enable_redis ? {
      "REDIS_URL" = "redis://${aws_elasticache_cluster.redis[0].cache_nodes[0].address}:${aws_elasticache_cluster.redis[0].cache_nodes[0].port}/0"
    } : {},
    var.enable_s3 ? {
      "AWS_S3_BUCKET" = aws_s3_bucket.app_storage[0].bucket
    } : {},
  )

  # User-provided env vars take precedence over computed infra vars
  computed_environment = merge(local.infra_environment, var.environment_variables)

  # Computed secrets from infrastructure resources
  infra_secrets = merge(
    {
      "APP_SECRET" = aws_ssm_parameter.app_secret.arn
    },
    var.enable_rds ? {
      "DATABASE_PASSWORD" = aws_ssm_parameter.db_password[0].arn
    } : {},
  )

  # User-provided secrets take precedence over computed infra secrets
  computed_secrets = merge(local.infra_secrets, var.secrets)
}

# =============================================================================
# App Secret
# =============================================================================

resource "random_password" "app_secret" {
  length  = 128
  special = false
}

resource "aws_ssm_parameter" "app_secret" {
  name        = "/${local.name_prefix}/app-secret"
  type        = "SecureString"
  value       = random_password.app_secret.result
  description = "Application secret for ${local.name_prefix}"

  tags = local.common_tags
}
