# S3バケット（静的ファイル用）
resource "aws_s3_bucket" "static_files" {
  bucket = "${var.project_name}-${var.environment}-static-files-${random_string.bucket_suffix.result}"

  tags = {
    Name = "${var.project_name}-${var.environment}-static-files"
  }
}

# バケット名にランダム文字列を追加（重複回避）
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3バケットの公開アクセスブロック設定
resource "aws_s3_bucket_public_access_block" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3バケットのバージョニング設定
resource "aws_s3_bucket_versioning" "static_files" {
  bucket = aws_s3_bucket.static_files.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3バケットの暗号化設定
resource "aws_s3_bucket_server_side_encryption_configuration" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "static_files" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "OAC for ${var.project_name} static files"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3バケットポリシー（CloudFrontからのアクセスのみ許可）
# Note: メインのTerraformファイルで定義されています

# S3バケットのウェブサイト設定
resource "aws_s3_bucket_website_configuration" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

# ライフサイクル設定（古いバージョンの自動削除）
resource "aws_s3_bucket_lifecycle_configuration" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  rule {
    id     = "delete_old_versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
