#!/bin/bash

# Next.js Multi SPA App デプロイスクリプト
# 使用方法: ./scripts/deploy.sh [environment] [image_tag]
# 例: ./scripts/deploy.sh dev v1.0.0

set -e

# 変数設定
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}
PROJECT_NAME="multi-spa-app"
AWS_REGION="ap-northeast-1"

# 色付きログ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件をチェックしています..."
    
    # 必要なコマンドの確認
    for cmd in aws docker terraform npm; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd がインストールされていません"
            exit 1
        fi
    done
    
    # AWS認証確認
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証が設定されていません"
        exit 1
    fi
    
    log_success "前提条件チェック完了"
}

# Terraformインフラデプロイ
deploy_infrastructure() {
    log_info "Terraformインフラをデプロイしています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    # terraform.tfvarsファイルの確認
    if [[ ! -f "terraform.tfvars" ]]; then
        log_warning "terraform.tfvarsファイルが見つかりません"
        log_info "terraform.tfvars.exampleをコピーして設定してください"
        cp terraform.tfvars.example terraform.tfvars
        log_warning "terraform.tfvarsファイルを編集してから再実行してください"
        exit 1
    fi
    
    terraform init
    terraform plan -var="ecr_image_tag=${IMAGE_TAG}"
    
    read -p "インフラをデプロイしますか? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply -var="ecr_image_tag=${IMAGE_TAG}" -auto-approve
        log_success "インフラデプロイ完了"
    else
        log_info "インフラデプロイをキャンセルしました"
        exit 0
    fi
    
    cd ../../../
}

# ECRリポジトリURIを取得
get_ecr_repository() {
    log_info "ECRリポジトリ情報を取得しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    ECR_REPOSITORY_URI=$(terraform output -raw ecr_repository_uri)
    cd ../../../
    
    if [[ -z "$ECR_REPOSITORY_URI" ]]; then
        log_error "ECRリポジトリURIを取得できませんでした"
        exit 1
    fi
    
    log_success "ECRリポジトリURI: $ECR_REPOSITORY_URI"
}

# Dockerイメージビルド・プッシュ
build_and_push_image() {
    log_info "Dockerイメージをビルド・プッシュしています..."
    
    # ECRログイン
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPOSITORY_URI}
    
    # Dockerイメージビルド
    log_info "Dockerイメージをビルドしています..."
    docker build --platform linux/amd64 -t ${PROJECT_NAME}:${IMAGE_TAG} .
    
    # タグ付け
    docker tag ${PROJECT_NAME}:${IMAGE_TAG} ${ECR_REPOSITORY_URI}:${IMAGE_TAG}
    
    # プッシュ
    log_info "ECRにプッシュしています..."
    docker push ${ECR_REPOSITORY_URI}:${IMAGE_TAG}
    
    log_success "Dockerイメージのビルド・プッシュ完了"
}

# 静的ファイルビルド・アップロード
deploy_static_files() {
    log_info "静的ファイルをビルド・アップロードしています..."
    
    # Next.js静的ビルド
    log_info "Next.jsアプリケーションをビルドしています..."
    npm install
    npm run build:static
    
    # S3バケット名を取得
    cd terraform/environments/${ENVIRONMENT}
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
    CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
    cd ../../../
    
    if [[ -z "$S3_BUCKET_NAME" ]]; then
        log_error "S3バケット名を取得できませんでした"
        exit 1
    fi
    
    # S3にアップロード
    log_info "S3にアップロードしています..."
    aws s3 sync ./out s3://${S3_BUCKET_NAME} --delete
    
    # CloudFrontキャッシュクリア
    log_info "CloudFrontキャッシュをクリアしています..."
    aws cloudfront create-invalidation --distribution-id ${CLOUDFRONT_DISTRIBUTION_ID} --paths "/*"
    
    log_success "静的ファイルのデプロイ完了"
}

# デプロイ情報表示
show_deployment_info() {
    log_info "デプロイ情報を表示しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    echo "=================================="
    echo "🚀 デプロイ完了!"
    echo "=================================="
    echo "環境: ${ENVIRONMENT}"
    echo "イメージタグ: ${IMAGE_TAG}"
    echo ""
    echo "📋 リソース情報:"
    echo "ECRリポジトリ: $(terraform output -raw ecr_repository_uri)"
    echo "S3バケット: $(terraform output -raw s3_bucket_name)"
    echo "App Runner URL: $(terraform output -raw app_runner_service_url)"
    echo "CloudFront ID: $(terraform output -raw cloudfront_distribution_id)"
    echo ""
    echo "🌐 ウェブサイトURL:"
    echo "$(terraform output -raw website_url)"
    echo "=================================="
    
    cd ../../../
}

# メイン処理
main() {
    log_info "Next.js Multi SPA App デプロイを開始します"
    log_info "環境: ${ENVIRONMENT}, イメージタグ: ${IMAGE_TAG}"
    
    check_prerequisites
    deploy_infrastructure
    get_ecr_repository
    build_and_push_image
    deploy_static_files
    show_deployment_info
    
    log_success "🎉 全てのデプロイが完了しました!"
}

# スクリプト実行
main "$@"
