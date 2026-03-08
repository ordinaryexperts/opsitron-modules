# Shared Services Module
#
# Creates shared infrastructure resources in a SharedServices account.
# Supports ECR repositories and S3 artifact buckets, each independently togglable.
#
# Resources created (when enabled):
# - ECR repository with encryption, scanning, and cross-account pull policy
# - ECR lifecycle policy for image cleanup
# - S3 bucket with versioning, encryption, and cross-account read policy
# - S3 lifecycle policy for artifact cleanup
#
# Usage:
#   module "shared_services" {
#     source = "github.com/ordinaryexperts/platform-modules//modules/shared-services?ref=shared-services-v1.0.0"
#
#     ecr_repository_name  = "123456789012-client-slug/web-app"
#     artifact_bucket_name = "123456789012-client-slug-artifacts"
#     organization_path    = "o-abc123/r-root/ou-workloads"
#   }

locals {
  common_tags = merge(var.tags, {
    ManagedBy    = "platform"
    ModuleSource = "github.com/ordinaryexperts/platform-modules//modules/shared-services"
  })
}

# =============================================================================
# ECR Repository
# =============================================================================

resource "aws_ecr_repository" "this" {
  count                = var.create_ecr_repository ? 1 : 0
  name                 = var.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = var.ecr_encryption_type
    kms_key         = var.ecr_encryption_type == "KMS" ? var.ecr_kms_key_arn : null
  }

  tags = merge(local.common_tags, {
    Name = var.ecr_repository_name
  })
}

# Cross-account pull policy
resource "aws_ecr_repository_policy" "cross_account" {
  count      = var.create_ecr_repository && var.organization_path != null ? 1 : 0
  repository = aws_ecr_repository.this[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Condition = {
          "ForAnyValue:StringLike" = {
            "aws:PrincipalOrgPaths" = ["${var.organization_path}/*"]
          }
        }
      }
    ]
  })
}

# Lifecycle policy
resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.create_ecr_repository && var.ecr_enable_lifecycle_policy ? 1 : 0
  repository = aws_ecr_repository.this[0].name

  policy = jsonencode({
    rules = concat(
      [
        {
          rulePriority = 1
          description  = "Remove untagged images after ${var.ecr_untagged_image_expiry_days} days"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = var.ecr_untagged_image_expiry_days
          }
          action = {
            type = "expire"
          }
        }
      ],
      var.ecr_max_image_count > 0 ? [
        {
          rulePriority = 2
          description  = "Keep only ${var.ecr_max_image_count} most recent tagged images"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = ["v", "sha-", "latest"]
            countType     = "imageCountMoreThan"
            countNumber   = var.ecr_max_image_count
          }
          action = {
            type = "expire"
          }
        }
      ] : []
    )
  })
}

# =============================================================================
# Artifact Bucket
# =============================================================================

resource "aws_s3_bucket" "artifacts" {
  count         = var.create_artifact_bucket ? 1 : 0
  bucket        = var.artifact_bucket_name != null ? var.artifact_bucket_name : null
  bucket_prefix = var.artifact_bucket_name == null ? var.artifact_bucket_prefix : null
  force_destroy = var.artifact_force_destroy

  tags = merge(local.common_tags, {
    Name    = var.artifact_bucket_name != null ? var.artifact_bucket_name : var.artifact_bucket_prefix
    Purpose = "build-artifacts"
  })
}

resource "aws_s3_bucket_versioning" "artifacts" {
  count  = var.create_artifact_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  versioning_configuration {
    status = var.artifact_enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  count  = var.create_artifact_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  count  = var.create_artifact_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cross-account read policy
resource "aws_s3_bucket_policy" "cross_account" {
  count  = var.create_artifact_bucket && var.organization_path != null ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountRead"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts[0].arn,
          "${aws_s3_bucket.artifacts[0].arn}/*"
        ]
        Condition = {
          "ForAnyValue:StringLike" = {
            "aws:PrincipalOrgPaths" = ["${var.organization_path}/*"]
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

# Lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  count  = var.create_artifact_bucket && var.artifact_enable_lifecycle_policy ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {
      prefix = "builds/"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.artifact_noncurrent_version_expiry_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.artifact_abort_incomplete_multipart_days
    }
  }
}
