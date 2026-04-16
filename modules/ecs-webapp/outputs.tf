# =============================================================================
# Core Outputs
# =============================================================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_name" {
  description = "Name of the app ECS service"
  value       = aws_ecs_service.app.name
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_zone_id" {
  description = "Route53 hosted zone ID of the ALB (for alias DNS records)"
  value       = aws_lb.main.zone_id
}

output "app_url" {
  description = "Application URL (HTTPS)"
  value       = local.app_url
}

output "container_image_tag_parameter_name" {
  description = "SSM parameter name that stores the current image tag (for CI/CD)"
  value       = aws_ssm_parameter.container_image_tag.name
}

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "alb_security_group_id" {
  description = "Security group ID of the ALB"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "Security group ID of the ECS service"
  value       = aws_security_group.ecs.id
}

output "sns_alerts_topic_arn" {
  description = "ARN of the SNS alerts topic (subscribe to receive alerts)"
  value       = aws_sns_topic.alerts.arn
}

# =============================================================================
# Database Outputs (conditional)
# =============================================================================

output "database_endpoint" {
  description = "Aurora cluster endpoint"
  value       = var.enable_rds ? aws_rds_cluster.main[0].endpoint : null
}

output "database_name" {
  description = "Database name"
  value       = var.enable_rds ? aws_rds_cluster.main[0].database_name : null
}

output "database_password_parameter_arn" {
  description = "ARN of the SSM parameter storing the database password"
  value       = var.enable_rds ? aws_ssm_parameter.db_password[0].arn : null
}

# =============================================================================
# Redis Outputs (conditional)
# =============================================================================

output "redis_endpoint" {
  description = "Redis cluster endpoint address"
  value       = var.enable_redis ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : null
}

output "redis_url" {
  description = "Full Redis connection URL"
  value       = var.enable_redis ? "redis://${aws_elasticache_cluster.redis[0].cache_nodes[0].address}:${aws_elasticache_cluster.redis[0].cache_nodes[0].port}/0" : null
}

# =============================================================================
# S3 Outputs (conditional)
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 storage bucket"
  value       = var.enable_s3 ? aws_s3_bucket.app_storage[0].bucket : null
}

output "s3_bucket_arn" {
  description = "ARN of the S3 storage bucket"
  value       = var.enable_s3 ? aws_s3_bucket.app_storage[0].arn : null
}

# =============================================================================
# Worker Outputs (conditional)
# =============================================================================

output "worker_service_name" {
  description = "Name of the worker ECS service"
  value       = var.enable_worker ? aws_ecs_service.worker[0].name : null
}

# =============================================================================
# SES Outputs (conditional)
# =============================================================================

output "ses_domain_identity_arn" {
  description = "ARN of the SES domain identity"
  value       = var.enable_ses ? aws_ses_domain_identity.main[0].arn : null
}

# =============================================================================
# SSM Parameter Outputs (for Platform deploy workflow discovery)
# =============================================================================

output "ssm_ecs_cluster_name_param" {
  description = "SSM parameter name containing the ECS cluster name"
  value       = aws_ssm_parameter.ecs_cluster_name.name
}

output "ssm_ecs_service_name_param" {
  description = "SSM parameter name containing the ECS service name"
  value       = aws_ssm_parameter.ecs_service_name.name
}

output "ssm_container_image_tag_param" {
  description = "SSM parameter name containing the current container image tag"
  value       = aws_ssm_parameter.container_image_tag.name
}
