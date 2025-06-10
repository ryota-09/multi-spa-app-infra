variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名"
  type        = string
  default     = "multi-spa-app"
}

variable "environment" {
  description = "環境名（dev, prod等）"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "ドメイン名（オプショナル）"
  type        = string
  default     = null
}

variable "app_runner_cpu" {
  description = "App RunnerのCPU設定"
  type        = string
  default     = "0.25 vCPU"
}

variable "app_runner_memory" {
  description = "App Runnerのメモリ設定"
  type        = string
  default     = "0.5 GB"
}

variable "ecr_image_tag" {
  description = "ECRイメージのタグ"
  type        = string
  default     = "latest"
}

variable "existing_ecr_repository_uri" {
  description = "既存のECRリポジトリURI（指定した場合は新しいECRリポジトリを作成しない）"
  type        = string
  default     = null
}

variable "cloudfront_price_class" {
  description = "CloudFrontの価格クラス"
  type        = string
  default     = "PriceClass_All"
  
  validation {
    condition = contains([
      "PriceClass_100",
      "PriceClass_200", 
      "PriceClass_All"
    ], var.cloudfront_price_class)
    error_message = "CloudFront価格クラスは PriceClass_100, PriceClass_200, PriceClass_All のいずれかである必要があります。"
  }
}

variable "enable_cloudfront_logging" {
  description = "CloudFrontアクセスログの有効化"
  type        = bool
  default     = false
}

variable "cloudfront_cache_ttl" {
  description = "CloudFrontキャッシュのTTL設定"
  type = object({
    default_ttl = number
    min_ttl     = number
    max_ttl     = number
  })
  default = {
    default_ttl = 86400  # 1日
    min_ttl     = 0
    max_ttl     = 31536000  # 1年
  }
}

variable "nextauth_url" {
  description = "NextAuth.jsのベースURL（指定しない場合はCloudFrontドメインを使用）"
  type        = string
  default     = null
}

variable "nextauth_secret" {
  description = "NextAuth.jsのシークレットキー"
  type        = string
  sensitive   = true
  default     = "default-secret-key-change-in-production"
}
