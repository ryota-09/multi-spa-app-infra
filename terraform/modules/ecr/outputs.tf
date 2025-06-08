output "repository_uri" {
  description = "ECRリポジトリのURI"
  value       = aws_ecr_repository.main.repository_url
}

output "repository_name" {
  description = "ECRリポジトリ名"
  value       = aws_ecr_repository.main.name
}

output "repository_arn" {
  description = "ECRリポジトリのARN"
  value       = aws_ecr_repository.main.arn
}

output "registry_id" {
  description = "ECRレジストリID"
  value       = aws_ecr_repository.main.registry_id
}
