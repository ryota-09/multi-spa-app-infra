output "service_url" {
  description = "App RunnerサービスのURL"
  value       = aws_apprunner_service.main.service_url
}

output "service_arn" {
  description = "App RunnerサービスのARN"
  value       = aws_apprunner_service.main.arn
}

output "service_id" {
  description = "App RunnerサービスのID"
  value       = aws_apprunner_service.main.service_id
}

output "status" {
  description = "App Runnerサービスのステータス"
  value       = aws_apprunner_service.main.status
}

output "instance_role_arn" {
  description = "App Runnerインスタンスロールの ARN"
  value       = aws_iam_role.app_runner_instance.arn
}

output "access_role_arn" {
  description = "App Runnerアクセスロールの ARN"
  value       = aws_iam_role.app_runner_access.arn
}

output "auto_scaling_configuration_arn" {
  description = "Auto Scaling設定のARN"
  value       = aws_apprunner_auto_scaling_configuration_version.main.arn
}

output "log_group_name" {
  description = "CloudWatch Log Groupの名前"
  value       = aws_cloudwatch_log_group.app_runner.name
}

output "ssm_parameter_name" {
  description = "SSM Parameter名（URL保存用）"
  value       = aws_ssm_parameter.app_runner_url.name
}
