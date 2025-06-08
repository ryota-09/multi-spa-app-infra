output "ecr_repository_uri" {
  description = "ECRリポジトリのURI"
  value       = var.existing_ecr_repository_uri != null ? var.existing_ecr_repository_uri : module.ecr[0].repository_uri
}

output "s3_bucket_name" {
  description = "S3バケット名"
  value       = module.s3.bucket_name
}

output "s3_bucket_website_endpoint" {
  description = "S3バケットの静的ウェブサイトエンドポイント"
  value       = module.s3.bucket_website_endpoint
}

output "app_runner_service_url" {
  description = "App RunnerサービスのURL"
  value       = module.app_runner.service_url
}

output "app_runner_service_arn" {
  description = "App RunnerサービスのARN"
  value       = module.app_runner.service_arn
}

output "cloudfront_distribution_id" {
  description = "CloudFrontディストリビューションID"
  value       = module.cloudfront.distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFrontドメイン名"
  value       = module.cloudfront.domain_name
}

output "website_url" {
  description = "ウェブサイトのURL"
  value       = "https://${module.cloudfront.domain_name}"
}

output "deployment_commands" {
  description = "デプロイコマンド"
  value = {
    ecr_repository = var.existing_ecr_repository_uri != null ? var.existing_ecr_repository_uri : module.ecr[0].repository_uri
    ecr_login = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${var.existing_ecr_repository_uri != null ? var.existing_ecr_repository_uri : module.ecr[0].repository_uri}"
    docker_build = "docker build --platform linux/amd64 -t ${var.project_name}:${var.ecr_image_tag} ."
    docker_tag = "docker tag ${var.project_name}:${var.ecr_image_tag} ${var.existing_ecr_repository_uri != null ? var.existing_ecr_repository_uri : module.ecr[0].repository_uri}:${var.ecr_image_tag}"
    docker_push = "docker push ${var.existing_ecr_repository_uri != null ? var.existing_ecr_repository_uri : module.ecr[0].repository_uri}:${var.ecr_image_tag}"
    s3_sync = "aws s3 sync ./out s3://${module.s3.bucket_name} --delete"
    cloudfront_invalidate = "aws cloudfront create-invalidation --distribution-id ${module.cloudfront.distribution_id} --paths '/*'"
  }
}
