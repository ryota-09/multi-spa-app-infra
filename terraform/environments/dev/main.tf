terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Terraform Stateの管理（オプショナル）
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "multi-spa-app/dev/terraform.tfstate"
  #   region = "ap-northeast-1"
  # }
}

module "multi_spa_app" {
  source = "../../"

  # 基本設定
  aws_region   = var.aws_region
  project_name = var.project_name
  environment  = "dev"

  # ドメイン設定（必要に応じて設定）
  domain_name = var.domain_name

  # ECRイメージタグ
  ecr_image_tag = var.ecr_image_tag

  # 既存のECRリポジトリを使用
  existing_ecr_repository_uri = var.existing_ecr_repository_uri

  # NextAuth.js設定
  nextauth_url    = var.nextauth_url
  nextauth_secret = var.nextauth_secret
}
