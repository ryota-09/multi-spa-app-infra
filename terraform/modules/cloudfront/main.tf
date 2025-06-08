# CloudFrontディストリビューション
resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_access_control_id = var.origin_access_control_id
    origin_id                = "S3-${var.s3_bucket_name}"
  }

  origin {
    domain_name = replace(var.app_runner_url, "https://", "")
    origin_id   = "AppRunner-${var.project_name}-${var.environment}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.project_name}-${var.environment}"
  default_root_object = "index.html"

  # カスタムエラーページ（SPAの場合）
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  # デフォルトキャッシュビヘイビア（静的コンテンツ）
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = var.default_cache_ttl
    max_ttl                = var.max_cache_ttl
    compress               = true
  }

  # API用のキャッシュビヘイビア（動的コンテンツ）
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "AppRunner-${var.project_name}-${var.environment}"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true

    # キャッシュを無効にするヘッダー
    response_headers_policy_id = aws_cloudfront_response_headers_policy.no_cache.id
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.domain_name == null ? true : false
    acm_certificate_arn           = var.domain_name != null ? var.acm_certificate_arn : null
    ssl_support_method            = var.domain_name != null ? "sni-only" : null
    minimum_protocol_version      = var.domain_name != null ? "TLSv1.2_2021" : null
  }

  aliases = var.domain_name != null ? [var.domain_name] : []

  # ログ設定（オプショナル）
  dynamic "logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      include_cookies = false
      bucket          = aws_s3_bucket.logs[0].bucket_domain_name
      prefix          = "cloudfront-logs/"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront"
  }
}

# レスポンスヘッダーポリシー（APIのキャッシュ無効化用）
resource "aws_cloudfront_response_headers_policy" "no_cache" {
  name    = "${var.project_name}-${var.environment}-no-cache"
  comment = "No cache policy for API responses"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      value    = "no-cache, no-store, must-revalidate"
      override = true
    }
    
    items {
      header   = "Pragma"
      value    = "no-cache"
      override = true
    }
    
    items {
      header   = "Expires"
      value    = "0"
      override = true
    }
  }
}

# CloudFrontアクセスログ用のS3バケット（オプショナル）
resource "aws_s3_bucket" "logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = "${var.project_name}-${var.environment}-cloudfront-logs-${random_string.log_bucket_suffix[0].result}"

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-logs"
  }
}

resource "random_string" "log_bucket_suffix" {
  count   = var.enable_logging ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

# ログバケットの設定
resource "aws_s3_bucket_public_access_block" "logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ログバケットのライフサイクル設定
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "delete_old_logs"
    status = "Enabled"

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}
