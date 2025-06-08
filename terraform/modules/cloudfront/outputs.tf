output "distribution_id" {
  description = "CloudFrontディストリビューションID"
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "CloudFrontディストリビューションARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "domain_name" {
  description = "CloudFrontドメイン名"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "distribution_status" {
  description = "CloudFrontディストリビューションのステータス"
  value       = aws_cloudfront_distribution.main.status
}

output "hosted_zone_id" {
  description = "CloudFrontのホストゾーンID"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "response_headers_policy_id" {
  description = "レスポンスヘッダーポリシーのID"
  value       = aws_cloudfront_response_headers_policy.no_cache.id
}

output "log_bucket_name" {
  description = "アクセスログ用S3バケット名"
  value       = var.enable_logging ? aws_s3_bucket.logs[0].bucket : null
}

output "log_bucket_domain_name" {
  description = "アクセスログ用S3バケットのドメイン名"
  value       = var.enable_logging ? aws_s3_bucket.logs[0].bucket_domain_name : null
}
