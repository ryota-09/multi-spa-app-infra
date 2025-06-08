variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境名（dev, prod等）"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3バケット名"
  type        = string
}

variable "s3_bucket_regional_domain_name" {
  description = "S3バケットのリージョナルドメイン名"
  type        = string
}

variable "origin_access_control_id" {
  description = "CloudFront Origin Access ControlのID"
  type        = string
}

variable "app_runner_url" {
  description = "App RunnerサービスのURL"
  type        = string
}

variable "domain_name" {
  description = "カスタムドメイン名（オプショナル）"
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ACM証明書のARN（カスタムドメイン使用時）"
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFrontの価格クラス"
  type        = string
  default     = "PriceClass_All"
}

variable "default_cache_ttl" {
  description = "デフォルトキャッシュTTL（秒）"
  type        = number
  default     = 86400
}

variable "max_cache_ttl" {
  description = "最大キャッシュTTL（秒）"
  type        = number
  default     = 31536000
}

variable "enable_logging" {
  description = "CloudFrontアクセスログの有効化"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "アクセスログの保持日数"
  type        = number
  default     = 30
}
