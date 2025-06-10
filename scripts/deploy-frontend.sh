#!/bin/bash

# フロントエンド静的サイトS3デプロイスクリプト
# 使用方法: ./scripts/deploy-frontend.sh [environment]
# 例: ./scripts/deploy-frontend.sh dev

set -e

# 変数設定
ENVIRONMENT=${1:-dev}
FRONTEND_DIR="frontend"

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
    for cmd in aws npm terraform; do
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

# S3バケット名とCloudFrontディストリビューションIDを取得
get_terraform_outputs() {
    log_info "Terraform出力値を取得しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    # S3バケット名を取得
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
    
    cd ../../../
    
    if [[ -z "$S3_BUCKET_NAME" ]]; then
        log_error "S3バケット名を取得できませんでした。インフラがデプロイされているか確認してください。"
        exit 1
    fi
    
    if [[ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
        log_error "CloudFrontディストリビューションIDを取得できませんでした。"
        exit 1
    fi
    
    log_success "S3バケット: $S3_BUCKET_NAME"
    log_success "CloudFrontディストリビューション: $CLOUDFRONT_DISTRIBUTION_ID"
}

# フロントエンドの静的ビルド
build_frontend() {
    log_info "フロントエンドの静的ビルドを開始します..."
    
    cd $FRONTEND_DIR
    
    # 依存関係のインストール
    log_info "依存関係をインストールしています..."
    npm install
    
    # 静的エクスポートビルド
    log_info "静的エクスポートビルドを実行しています..."
    npm run build:static
    
    # outディレクトリの確認
    if [[ ! -d "out" ]]; then
        log_error "静的ビルドが失敗しました。outディレクトリが見つかりません。"
        exit 1
    fi
    
    log_success "静的ビルド完了"
    cd ..
}

# S3にアップロード
upload_to_s3() {
    log_info "S3にアップロードしています..."
    
    # 既存ファイルを削除してから新しいファイルをアップロード
    aws s3 sync ./${FRONTEND_DIR}/out s3://${S3_BUCKET_NAME} --delete
    
    log_success "S3アップロード完了"
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
    
    # 無効化完了まで待機（オプション）
    aws cloudfront wait invalidation-completed \
        --distribution-id ${CLOUDFRONT_DISTRIBUTION_ID} \
        --id ${INVALIDATION_ID}
    
    log_success "CloudFrontキャッシュ無効化完了"
}

# デプロイ情報表示
show_deployment_info() {
    log_info "デプロイ情報を表示しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    echo "=================================="
    echo "🌐 フロントエンドデプロイ完了!"
    echo "=================================="
    echo "環境: ${ENVIRONMENT}"
    echo ""
    echo "📋 リソース情報:"
    echo "S3バケット: ${S3_BUCKET_NAME}"
    echo "CloudFront ID: ${CLOUDFRONT_DISTRIBUTION_ID}"
    echo ""
    echo "🌐 ウェブサイトURL:"
    echo "$(terraform output -raw website_url)"
    echo ""
    echo "📁 デプロイされたファイル:"
    ls -la ../../${FRONTEND_DIR}/out/ | head -10
    echo "=================================="
    
    cd ../../../
}

# メイン処理
main() {
    log_info "フロントエンド静的サイトデプロイを開始します"
    log_info "環境: ${ENVIRONMENT}"
    
    check_prerequisites
    get_terraform_outputs
    build_frontend
    upload_to_s3
    invalidate_cloudfront
    show_deployment_info
    
    log_success "🎉 フロントエンドデプロイが完了しました!"
}

# スクリプト実行
main "$@"
