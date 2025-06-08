variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境名（dev, prod等）"
  type        = string
}

variable "ecr_repository_uri" {
  description = "ECRリポジトリのURI"
  type        = string
}

variable "image_tag" {
  description = "コンテナイメージのタグ"
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "App RunnerのCPU設定"
  type        = string
  default     = "0.25 vCPU"
}

variable "memory" {
  description = "App Runnerのメモリ設定"
  type        = string
  default     = "0.5 GB"
}

variable "auto_deployments_enabled" {
  description = "自動デプロイの有効化"
  type        = bool
  default     = true
}

variable "max_concurrency" {
  description = "最大同時接続数"
  type        = number
  default     = 100
}

variable "max_size" {
  description = "最大インスタンス数"
  type        = number
  default     = 10
}

variable "min_size" {
  description = "最小インスタンス数"
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "CloudWatch Logsの保持日数"
  type        = number
  default     = 7
}
