variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境名（dev, prod等）"
  type        = string
}

variable "domain_name" {
  description = "ドメイン名（オプショナル）"
  type        = string
  default     = null
}

variable "cloudfront_distribution_arn" {
  description = "CloudFrontディストリビューションのARN"
  type        = string
  default     = ""
}
