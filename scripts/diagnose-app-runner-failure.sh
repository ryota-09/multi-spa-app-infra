#!/bin/bash

# App Runnerの失敗診断スクリプト
set -e

REGION="ap-northeast-1"
SERVICE_NAME="multi-spa-app-dev"

echo "=== App Runner Service Failure Diagnosis ==="
echo ""

# 1. App Runnerサービスの詳細情報を取得
echo "1. Getting App Runner service details..."
SERVICE_ARN=$(aws apprunner list-services --region $REGION --query "ServiceSummaryList[?ServiceName=='$SERVICE_NAME'].ServiceArn" --output text)

if [ -z "$SERVICE_ARN" ]; then
    echo "Error: App Runner service not found: $SERVICE_NAME"
    exit 1
fi

echo "Service ARN: $SERVICE_ARN"
echo ""

# 2. サービスの詳細情報を表示
echo "2. Service details:"
aws apprunner describe-service --service-arn $SERVICE_ARN --region $REGION --query 'Service.{Status:Status,ServiceName:ServiceName,CreatedAt:CreatedAt,UpdatedAt:UpdatedAt}' --output table
echo ""

# 3. 最新のオペレーションを確認
echo "3. Recent operations:"
aws apprunner list-operations --service-arn $SERVICE_ARN --region $REGION --query 'OperationSummaryList[0:5].{Type:Type,Status:Status,StartedAt:StartedAt,EndedAt:EndedAt}' --output table
echo ""

# 4. CloudWatch Logsでエラーログを確認
echo "4. Checking CloudWatch Logs for errors..."
LOG_GROUP="/aws/apprunner/$SERVICE_NAME/application"

# ログストリームの存在確認
STREAMS=$(aws logs describe-log-streams --log-group-name $LOG_GROUP --region $REGION --query 'logStreams[0:3].logStreamName' --output text 2>/dev/null || echo "")

if [ -n "$STREAMS" ]; then
    echo "Recent log streams found. Checking for errors..."
    for STREAM in $STREAMS; do
        echo "Stream: $STREAM"
        aws logs filter-log-events --log-group-name $LOG_GROUP --log-stream-names $STREAM --region $REGION --filter-pattern "ERROR" --max-items 10 --query 'events[*].message' --output text 2>/dev/null || echo "No error logs found"
        echo ""
    done
else
    echo "No log streams found. The service may have failed before creating logs."
fi
echo ""

# 5. ECRイメージの確認
echo "5. Checking ECR image availability..."
ECR_URI=$(aws apprunner describe-service --service-arn $SERVICE_ARN --region $REGION --query 'Service.SourceConfiguration.ImageRepository.ImageIdentifier' --output text)
echo "Configured image: $ECR_URI"

if [[ $ECR_URI == *"ecr"* ]]; then
    REPO_NAME=$(echo $ECR_URI | awk -F'/' '{print $2}' | awk -F':' '{print $1}')
    TAG=$(echo $ECR_URI | awk -F':' '{print $2}')
    
    echo "Repository: $REPO_NAME"
    echo "Tag: $TAG"
    
    # イメージが存在するか確認
    IMAGE_EXISTS=$(aws ecr describe-images --repository-name $REPO_NAME --region $REGION --image-ids imageTag=$TAG --query 'imageDetails[0].imageTags[0]' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$IMAGE_EXISTS" = "NOT_FOUND" ]; then
        echo "ERROR: Image not found in ECR!"
        echo "Available tags in repository:"
        aws ecr describe-images --repository-name $REPO_NAME --region $REGION --query 'imageDetails[*].imageTags[0]' --output text | head -10
    else
        echo "Image exists in ECR: ✓"
    fi
fi
echo ""

# 6. IAMロールの確認
echo "6. Checking IAM roles..."
ACCESS_ROLE=$(aws apprunner describe-service --service-arn $SERVICE_ARN --region $REGION --query 'Service.SourceConfiguration.AuthenticationConfiguration.AccessRoleArn' --output text)
INSTANCE_ROLE=$(aws apprunner describe-service --service-arn $SERVICE_ARN --region $REGION --query 'Service.InstanceConfiguration.InstanceRoleArn' --output text)

echo "Access Role: $ACCESS_ROLE"
echo "Instance Role: $INSTANCE_ROLE"

# アクセスロールのポリシー確認
if [ -n "$ACCESS_ROLE" ] && [ "$ACCESS_ROLE" != "None" ]; then
    ROLE_NAME=$(echo $ACCESS_ROLE | awk -F'/' '{print $NF}')
    echo "Checking access role policies..."
    aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[*].PolicyName' --output text
fi
echo ""

# 7. ヘルスチェックの設定確認
echo "7. Health check configuration:"
aws apprunner describe-service --service-arn $SERVICE_ARN --region $REGION --query 'Service.HealthCheckConfiguration' --output json
echo ""

# 8. 推奨事項
echo "=== Recommendations ==="
echo "1. Verify that the Docker image exists in ECR with the correct tag"
echo "2. Check if the Docker image runs correctly locally with: docker run -p 3000:3000 <image>"
echo "3. Ensure the health check path returns 200 OK"
echo "4. Verify IAM roles have necessary permissions"
echo "5. Check if the application starts on port 3000"
echo ""

# 9. 再デプロイの提案
echo "To retry deployment:"
echo "1. Fix any identified issues"
echo "2. Rebuild and push Docker image: cd frontend && docker build -t <image> . && docker push <image>"
echo "3. Update App Runner service: aws apprunner update-service --service-arn $SERVICE_ARN --source-configuration '{...}'"
echo "   OR"
echo "   Redeploy with: ./scripts/deploy.sh dev latest"