# App Runner用のIAMロール
resource "aws_iam_role" "app_runner_instance" {
  name = "${var.project_name}-${var.environment}-app-runner-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-app-runner-instance"
  }
}

# App Runner用のアクセスロール（ECRからイメージを取得するため）
resource "aws_iam_role" "app_runner_access" {
  name = "${var.project_name}-${var.environment}-app-runner-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-app-runner-access"
  }
}

# ECRアクセス用のポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "app_runner_access_ecr" {
  role       = aws_iam_role.app_runner_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# App Runnerサービス
resource "aws_apprunner_service" "main" {
  service_name = "${var.project_name}-${var.environment}"

  source_configuration {
    auto_deployments_enabled = var.auto_deployments_enabled
    
    image_repository {
      image_configuration {
        port = "3000"
        runtime_environment_variables = {
          NODE_ENV   = "production"
          STANDALONE = "true"
          HOSTNAME   = "0.0.0.0"
          PORT       = "3000"
        }
        start_command = "node server.js"
      }
      image_identifier      = "${var.ecr_repository_uri}:${var.image_tag}"
      image_repository_type = "ECR"
    }
    
    authentication_configuration {
      access_role_arn = aws_iam_role.app_runner_access.arn
    }
  }

  instance_configuration {
    cpu               = "512"
    memory            = "1024"
    instance_role_arn = aws_iam_role.app_runner_instance.arn
  }

  health_check_configuration {
    healthy_threshold   = 1
    interval            = 20
    path                = "/"
    protocol            = "HTTP"
    timeout             = 15
    unhealthy_threshold = 10
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.main.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-app-runner"
  }
}

# App Runnerのオートスケーリング設定
resource "aws_apprunner_auto_scaling_configuration_version" "main" {
  auto_scaling_configuration_name = "${var.project_name}-${var.environment}-autoscaling"

  max_concurrency = var.max_concurrency
  max_size        = var.max_size
  min_size        = var.min_size

  tags = {
    Name = "${var.project_name}-${var.environment}-autoscaling"
  }
}

# SSM Parameter Store（App Runner URLを保存）
resource "aws_ssm_parameter" "app_runner_url" {
  name  = "/${var.project_name}/${var.environment}/app-runner/url"
  type  = "String"
  value = aws_apprunner_service.main.service_url

  tags = {
    Name = "${var.project_name}-${var.environment}-app-runner-url"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app_runner" {
  name              = "/aws/apprunner/${var.project_name}-${var.environment}/application"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-app-runner-logs"
  }
}
