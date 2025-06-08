output "ecr_repository_uri" {
  description = "ECRリポジトリのURI"
  value       = module.multi_spa_app.ecr_repository_uri
}

output "s3_bucket_name" {
  description = "S3バケット名"
  value       = module.multi_spa_app.s3_bucket_name
}

output "app_runner_service_url" {
  description = "App RunnerサービスのURL"
  value       = module.multi_spa_app.app_runner_service_url
}

output "cloudfront_distribution_id" {
  description = "CloudFrontディストリビューションID"
  value       = module.multi_spa_app.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFrontドメイン名"
  value       = module.multi_spa_app.cloudfront_domain_name
}

output "website_url" {
  description = "ウェブサイトのURL"
  value       = module.multi_spa_app.website_url
}

output "deployment_commands" {
  description = "デプロイコマンド"
  value       = module.multi_spa_app.deployment_commands
}
