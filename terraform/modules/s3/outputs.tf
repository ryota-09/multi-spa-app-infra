output "bucket_name" {
  description = "S3バケット名"
  value       = aws_s3_bucket.static_files.bucket
}

output "bucket_arn" {
  description = "S3バケットのARN"
  value       = aws_s3_bucket.static_files.arn
}

output "bucket_regional_domain_name" {
  description = "S3バケットのリージョナルドメイン名"
  value       = aws_s3_bucket.static_files.bucket_regional_domain_name
}

output "bucket_website_endpoint" {
  description = "S3バケットの静的ウェブサイトエンドポイント"
  value       = aws_s3_bucket_website_configuration.static_files.website_endpoint
}

output "origin_access_control_id" {
  description = "CloudFront Origin Access ControlのID"
  value       = aws_cloudfront_origin_access_control.static_files.id
}

output "origin_access_control_etag" {
  description = "CloudFront Origin Access ControlのETag"
  value       = aws_cloudfront_origin_access_control.static_files.etag
}
