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

  # カスタムエラーレスポンスを削除
  # 動的ルート(/login, /api等)は各オリジンで適切に処理される

  # デフォルトキャッシュビヘイビア（静的コンテンツ）
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    # マネージドキャッシュポリシーを使用（静的コンテンツ用）
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CACHING_OPTIMIZED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # ログインページ用のキャッシュビヘイビア（動的コンテンツ）
  # /login および /login/* パスに対応
  ordered_cache_behavior {
    path_pattern     = "/login*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "AppRunner-${var.project_name}-${var.environment}"

    # キャッシュ無効化ポリシーを適用
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CACHING_DISABLED
    
    # NextAuth.js用にHost以外のすべてのヘッダー、Cookie、クエリパラメータを転送
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # API用のキャッシュビヘイビア（動的コンテンツ）
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "AppRunner-${var.project_name}-${var.environment}"

    # キャッシュ無効化ポリシーを適用
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CACHING_DISABLED
    
    # NextAuth.js用にすべてのヘッダー、Cookie、クエリパラメータを転送
    origin_request_policy_id = "33f36d7e-f396-46d9-90e0-52428a34d9dc" # AllViewer

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # テストルート用のキャッシュビヘイビア（動的コンテンツ）
  ordered_cache_behavior {
    path_pattern     = "/test-route*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "AppRunner-${var.project_name}-${var.environment}"

    # キャッシュ無効化ポリシーを適用
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CACHING_DISABLED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # Next.js静的アセット用のキャッシュビヘイビア（長期キャッシュ）
  ordered_cache_behavior {
    path_pattern     = "/_next/static/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    # 静的アセットは長期キャッシュ（ファイル名にハッシュが含まれるため）
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CACHING_OPTIMIZED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # 画像とアイコン用のキャッシュビヘイビア
  ordered_cache_behavior {
    path_pattern     = "*.ico"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    # 静的リソースは長期キャッシュ
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CACHING_OPTIMIZED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # SVGファイル用のキャッシュビヘイビア
  ordered_cache_behavior {
    path_pattern     = "*.svg"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    # 静的リソースは長期キャッシュ
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CACHING_OPTIMIZED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # 画像ファイル用のキャッシュビヘイビア
  ordered_cache_behavior {
    path_pattern     = "/images/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    # 静的リソースは長期キャッシュ
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CACHING_OPTIMIZED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # HTMLファイル用のキャッシュビヘイビア（短期キャッシュ）
  ordered_cache_behavior {
    path_pattern     = "*.html"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    # HTMLファイルは短期キャッシュ
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CACHING_DISABLED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # ルートパス用のキャッシュビヘイビア（短期キャッシュ）
  ordered_cache_behavior {
    path_pattern     = "/"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    # ルートページは短期キャッシュ
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CACHING_DISABLED

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
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

    filter {
      prefix = "cloudfront-logs/"
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}
