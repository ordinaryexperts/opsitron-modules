# Static Website Module
#
# Creates an S3-backed static website with CloudFront distribution.
# Designed for use with OE Platform's S3 artifact deployment workflow.
#
# Resources created:
# - S3 bucket for website content (private, accessed via CloudFront OAC)
# - CloudFront distribution with custom domain and SSL
# - CloudFront Origin Access Control for secure S3 access
# - S3 bucket policy allowing CloudFront OAC access
# - SSM parameters for Platform integration (distribution ID, bucket name)
#
# Usage:
#   module "website" {
#     source = "github.com/org/platform-modules//modules/static-website?ref=static-website-v1.0.0"
#
#     name            = "web-app"
#     environment     = "prod1"
#     domain          = "www.example.com"
#     certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/..."
#   }

locals {
  bucket_prefix = "${var.name}-${var.environment}-"
  # SSM parameter names follow Platform conventions
  ssm_prefix = "/${var.name}/${var.environment}"
}

# =============================================================================
# S3 Bucket for Website Content
# =============================================================================

resource "aws_s3_bucket" "website" {
  bucket_prefix = local.bucket_prefix

  tags = merge(var.tags, {
    Name        = "${var.name}-${var.environment}"
    Environment = var.environment
    Purpose     = "static-website"
  })
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# CloudFront Origin Access Control
# =============================================================================

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.name}-${var.environment}-oac"
  description                       = "OAC for ${var.name} ${var.environment} static website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# =============================================================================
# S3 Bucket Policy for CloudFront OAC
# =============================================================================

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.website]
}

# =============================================================================
# CloudFront Function for URL Rewriting
# =============================================================================
#
# Rewrites directory requests to index.html for multi-page static sites.
# e.g., /about/ → /about/index.html, /about → /about/index.html
# Requests with file extensions are passed through unchanged.
#

resource "aws_cloudfront_function" "url_rewrite" {
  name    = "${var.name}-${var.environment}-url-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite directory URLs to index.html for ${var.name} ${var.environment}"
  publish = true
  code    = <<-EOF
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // If URI has a file extension, pass through unchanged
  if (uri.includes('.')) {
    return request;
  }

  // Append /index.html for directory paths
  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
  } else {
    request.uri = uri + '/index.html';
  }

  return request;
}
EOF
}

# =============================================================================
# CloudFront Distribution
# =============================================================================

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.default_root_object
  aliases             = [var.domain]
  price_class         = var.price_class
  web_acl_id          = var.waf_acl_arn

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.website.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.url_rewrite.arn
    }

    # Cache settings for static assets
    min_ttl     = 0
    default_ttl = 86400    # 1 day
    max_ttl     = 31536000 # 1 year
  }

  # SPA-friendly error handling
  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code         = custom_error_response.value.error_code
      response_code      = custom_error_response.value.response_code
      response_page_path = custom_error_response.value.response_page_path
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_protocol_version
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Optional logging
  dynamic "logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      bucket          = var.logging_bucket
      prefix          = var.logging_prefix
      include_cookies = false
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.name}-${var.environment}-cdn"
    Environment = var.environment
  })
}

# =============================================================================
# SSM Parameters for Platform Integration
# =============================================================================

# CloudFront distribution ID - used by deploy workflow to invalidate cache
resource "aws_ssm_parameter" "distribution_id" {
  name        = "${local.ssm_prefix}/cloudfront-distribution-id"
  description = "CloudFront distribution ID for ${var.name} ${var.environment}"
  type        = "String"
  value       = aws_cloudfront_distribution.website.id

  tags = var.tags
}

# Website bucket name - for reference
resource "aws_ssm_parameter" "website_bucket" {
  name        = "${local.ssm_prefix}/website-bucket-name"
  description = "S3 bucket name for ${var.name} ${var.environment} website content"
  type        = "String"
  value       = aws_s3_bucket.website.id

  tags = var.tags
}

# Artifact key - updated by deploy workflow to track current deployment
resource "aws_ssm_parameter" "artifact_key" {
  name        = "${local.ssm_prefix}/artifact-key"
  description = "Current artifact key deployed to ${var.name} ${var.environment}"
  type        = "String"
  value       = "not-deployed-yet"

  # Ignore changes to value - managed by deploy workflow
  lifecycle {
    ignore_changes = [value]
  }

  tags = var.tags
}
