# =============================================================================
# S3 Application Storage Bucket (conditional on enable_s3)
# =============================================================================

resource "aws_s3_bucket" "app_storage" {
  count = var.enable_s3 ? 1 : 0

  bucket = "${local.name_prefix}-storage-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-storage"
  })
}

resource "aws_s3_bucket_versioning" "app_storage" {
  count = var.enable_s3 ? 1 : 0

  bucket = aws_s3_bucket.app_storage[0].id
  versioning_configuration {
    status = local.is_prod ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "app_storage" {
  count = var.enable_s3 ? 1 : 0

  bucket = aws_s3_bucket.app_storage[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_storage" {
  count = var.enable_s3 ? 1 : 0

  bucket = aws_s3_bucket.app_storage[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "app_storage" {
  count = var.enable_s3 ? 1 : 0

  bucket = aws_s3_bucket.app_storage[0].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = [local.app_url]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "app_storage" {
  count = var.enable_s3 && local.is_prod ? 1 : 0

  bucket = aws_s3_bucket.app_storage[0].id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
