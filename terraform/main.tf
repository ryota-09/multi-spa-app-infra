terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ECRリポジトリ（既存のECRが指定されていない場合のみ作成）
module "ecr" {
  count = var.existing_ecr_repository_uri == null ? 1 : 0
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

# S3バケット（静的ファイル）
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
}

# App Runner（動的API）
module "app_runner" {
  source = "./modules/app-runner"

  project_name = var.project_name
  environment  = var.environment
  ecr_repository_uri = var.existing_ecr_repository_uri != null ? var.existing_ecr_repository_uri : module.ecr[0].repository_uri
  image_tag    = var.ecr_image_tag
  
  depends_on = [module.ecr]
}

# CloudFront（CDN）
module "cloudfront" {
  source = "./modules/cloudfront"

  project_name = var.project_name
  environment  = var.environment
  
  # S3オリジン設定
  s3_bucket_name                = module.s3.bucket_name
  s3_bucket_regional_domain_name = module.s3.bucket_regional_domain_name
  origin_access_control_id      = module.s3.origin_access_control_id
  
  # App Runnerオリジン設定
  app_runner_url = module.app_runner.service_url
  
  # ドメイン設定
  domain_name = var.domain_name
  
  depends_on = [module.s3, module.app_runner]
}

# S3バケットポリシー（CloudFront作成後に適用）
resource "aws_s3_bucket_policy" "static_files" {
  bucket = module.s3.bucket_name
  depends_on = [module.cloudfront]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${module.s3.bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.distribution_arn
          }
        }
      }
    ]
  })
}
