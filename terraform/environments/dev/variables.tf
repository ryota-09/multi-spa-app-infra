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

variable "domain_name" {
  description = "ドメイン名（オプショナル）"
  type        = string
  default     = null
}

variable "ecr_image_tag" {
  description = "ECRイメージのタグ"
  type        = string
  default     = "latest"
}

variable "existing_ecr_repository_uri" {
  description = "既存のECRリポジトリURI"
  type        = string
  default     = null
}
