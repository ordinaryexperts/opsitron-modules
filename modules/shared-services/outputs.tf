# =============================================================================
# ECR Outputs
# =============================================================================

output "ecr_repositories" {
  description = "Map of application slug to ECR repository details"
  value = {
    for slug, repo in aws_ecr_repository.app : slug => {
      name        = repo.name
      arn         = repo.arn
      url         = repo.repository_url
      registry_id = repo.registry_id
    }
  }
}

# =============================================================================
# Artifact Bucket Outputs
# =============================================================================

output "artifact_bucket_name" {
  description = "Name of the S3 artifact bucket"
  value       = var.create_artifact_bucket ? aws_s3_bucket.artifacts[0].id : null
}

output "artifact_bucket_arn" {
  description = "ARN of the S3 artifact bucket"
  value       = var.create_artifact_bucket ? aws_s3_bucket.artifacts[0].arn : null
}

output "artifact_bucket_domain_name" {
  description = "Domain name of the S3 artifact bucket"
  value       = var.create_artifact_bucket ? aws_s3_bucket.artifacts[0].bucket_domain_name : null
}

output "artifact_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 artifact bucket"
  value       = var.create_artifact_bucket ? aws_s3_bucket.artifacts[0].bucket_regional_domain_name : null
}

output "artifact_bucket_region" {
  description = "AWS region where the artifact bucket is located"
  value       = var.create_artifact_bucket ? aws_s3_bucket.artifacts[0].region : null
}
