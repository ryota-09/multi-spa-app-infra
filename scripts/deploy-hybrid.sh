#!/bin/bash

# ハイブリッドデプロイスクリプト
# S3とApp Runnerに同じビルドアーティファクトをデプロイする
# 使用方法: ./scripts/deploy-hybrid.sh [environment]

set -e

# 変数設定
ENVIRONMENT=${1:-dev}
FRONTEND_DIR="frontend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
    
    # フロントエンドディレクトリの確認
    if [[ ! -d "$FRONTEND_DIR" ]]; then
        log_error "frontendディレクトリが見つかりません"
        exit 1
    fi
    
    # 必要なコマンドの確認
    for cmd in aws npm docker terraform; do
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

# Terraformから必要な値を取得
get_terraform_outputs() {
    log_info "Terraform出力値を取得しています..."
    
    cd "${PROJECT_ROOT}/terraform/environments/${ENVIRONMENT}"
    
    # 必要な値を取得
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_uri 2>/dev/null || echo "")
    APP_RUNNER_SERVICE_URL=$(terraform output -raw app_runner_service_url 2>/dev/null || echo "")
    
    cd "${PROJECT_ROOT}"
    
    if [[ -z "$S3_BUCKET_NAME" ]] || [[ -z "$ECR_REPOSITORY_URL" ]]; then
        log_error "必要なリソースの情報を取得できませんでした。インフラがデプロイされているか確認してください。"
        exit 1
    fi
    
    # CloudFrontディストリビューションIDを取得
    CLOUDFRONT_DISTRIBUTION_ID=$(aws cloudfront list-distributions \
        --query "DistributionList.Items[?Origins.Items[0].DomainName=='${S3_BUCKET_NAME}.s3.ap-northeast-1.amazonaws.com'].Id" \
        --output text 2>/dev/null || echo "")
    
    # App RunnerサービスARNを取得
    if [[ -n "$APP_RUNNER_SERVICE_URL" ]]; then
        SERVICE_NAME=$(echo "$APP_RUNNER_SERVICE_URL" | cut -d'.' -f1)
        APP_RUNNER_SERVICE_ARN=$(aws apprunner list-services \
            --query "ServiceSummaryList[?ServiceName=='multi-spa-app-dev'].ServiceArn" \
            --output text 2>/dev/null || echo "")
    fi
    
    log_success "リソース情報取得完了"
}

# 統一ビルドの実行
build_unified() {
    log_info "統一ビルドを開始します..."
    
    cd "${PROJECT_ROOT}/${FRONTEND_DIR}"
    
    # 既存のビルド出力をクリア
    log_info "既存のビルド出力をクリア中..."
    rm -rf .next out
    
    # 依存関係のインストール
    log_info "依存関係をインストールしています..."
    npm install
    
    # ハイブリッドビルドの実行
    log_info "ハイブリッドビルドを実行中..."
    npm run build:hybrid
    
    # ビルド結果の確認
    if [[ ! -d "out" ]] || [[ ! -d ".next/standalone" ]]; then
        log_error "ビルドが失敗しました。必要なディレクトリが見つかりません。"
        exit 1
    fi
    
    log_success "統一ビルド完了"
    cd "${PROJECT_ROOT}"
}

# S3にアップロード
upload_to_s3() {
    log_info "S3に静的ファイルをアップロードしています..."
    
    # 既存ファイルを削除してから新しいファイルをアップロード
    aws s3 sync "${FRONTEND_DIR}/out" "s3://${S3_BUCKET_NAME}" --delete
    
    log_success "S3アップロード完了"
}

# Dockerイメージのビルドとプッシュ
build_and_push_docker() {
    log_info "Dockerイメージをビルドしています..."
    
    cd "${PROJECT_ROOT}/${FRONTEND_DIR}"
    
    # ECRにログイン
    log_info "ECRにログインしています..."
    aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${ECR_REPOSITORY_URL}
    
    # プレビルドイメージの作成
    log_info "プレビルドDockerイメージを作成中..."
    docker build -f Dockerfile.prebuilt -t ${ECR_REPOSITORY_URL}:latest .
    
    # イメージのタグ付け
    docker tag ${ECR_REPOSITORY_URL}:latest ${ECR_REPOSITORY_URL}:${ENVIRONMENT}
    
    # イメージのプッシュ
    log_info "ECRにイメージをプッシュしています..."
    docker push ${ECR_REPOSITORY_URL}:latest
    docker push ${ECR_REPOSITORY_URL}:${ENVIRONMENT}
    
    cd "${PROJECT_ROOT}"
    
    log_success "Dockerイメージのビルドとプッシュ完了"
}

# App Runnerサービスの更新
update_app_runner() {
    log_info "App Runnerサービスを更新しています..."
    
    # App Runnerデプロイメント開始
    DEPLOYMENT_ID=$(aws apprunner start-deployment \
        --service-arn ${APP_RUNNER_SERVICE_ARN} \
        --query 'OperationId' \
        --output text)
    
    log_info "デプロイメントID: ${DEPLOYMENT_ID}"
    
    # デプロイメント完了待機
    log_info "App Runnerデプロイメントの完了を待っています..."
    
    while true; do
        STATUS=$(aws apprunner describe-service \
            --service-arn ${APP_RUNNER_SERVICE_ARN} \
            --query 'Service.Status' \
            --output text)
        
        if [[ "$STATUS" == "RUNNING" ]]; then
            log_success "App Runnerデプロイメント完了"
            break
        elif [[ "$STATUS" == "OPERATION_IN_PROGRESS" ]]; then
            echo -n "."
            sleep 10
        else
            log_error "App Runnerデプロイメントが失敗しました。ステータス: $STATUS"
            exit 1
        fi
    done
}

# CloudFrontキャッシュの無効化
invalidate_cloudfront() {
    log_info "CloudFrontキャッシュを無効化しています..."
    
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id ${CLOUDFRONT_DISTRIBUTION_ID} \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    
    log_info "無効化ID: $INVALIDATION_ID"
    log_info "無効化の完了を待っています..."
    
    aws cloudfront wait invalidation-completed \
        --distribution-id ${CLOUDFRONT_DISTRIBUTION_ID} \
        --id ${INVALIDATION_ID}
    
    log_success "CloudFrontキャッシュ無効化完了"
}

# デプロイ情報表示
show_deployment_info() {
    log_info "デプロイ情報"
    
    cd "${PROJECT_ROOT}/terraform/environments/${ENVIRONMENT}"
    
    echo "=================================="
    echo "🚀 ハイブリッドデプロイ完了!"
    echo "=================================="
    echo "環境: ${ENVIRONMENT}"
    echo ""
    echo "📋 リソース情報:"
    echo "S3バケット: ${S3_BUCKET_NAME}"
    echo "ECRリポジトリ: ${ECR_REPOSITORY_URL}"
    echo "App Runner: ${APP_RUNNER_SERVICE_NAME}"
    echo "CloudFront: ${CLOUDFRONT_DISTRIBUTION_ID}"
    echo ""
    echo "🌐 ウェブサイトURL:"
    echo "$(terraform output -raw website_url)"
    echo ""
    echo "✅ デプロイ内容:"
    echo "- 静的ページ: S3経由で配信"
    echo "- 動的ページ: App Runner経由で配信"
    echo "- 統一ビルド: 同一のJSファイルハッシュを使用"
    echo "=================================="
    
    cd "${PROJECT_ROOT}"
}

# メイン処理
main() {
    log_info "ハイブリッドデプロイを開始します"
    log_info "環境: ${ENVIRONMENT}"
    
    check_prerequisites
    get_terraform_outputs
    build_unified
    upload_to_s3
    build_and_push_docker
    update_app_runner
    invalidate_cloudfront
    show_deployment_info
    
    log_success "🎉 ハイブリッドデプロイが完了しました!"
}

# スクリプト実行
main "$@"