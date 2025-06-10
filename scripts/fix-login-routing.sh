#!/bin/bash

# ログインページルーティング修正スクリプト
# 使用方法: ./scripts/fix-login-routing.sh [environment]

set -e

# 変数設定
ENVIRONMENT=${1:-dev}

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
    for cmd in terraform aws npm; do
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

# CloudFrontディストリビューションIDを取得
get_cloudfront_info() {
    log_info "CloudFrontディストリビューションIDを取得しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
    
    cd ../../../
    
    if [[ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
        log_error "CloudFrontディストリビューションIDを取得できませんでした。"
        exit 1
    fi
    
    log_success "CloudFrontディストリビューション: $CLOUDFRONT_DISTRIBUTION_ID"
}

# 静的サイトを再ビルド（ログインページを除外）
rebuild_static_site() {
    log_info "静的サイトを再ビルドしています（ログインページを除外）..."
    
    cd frontend
    
    # 依存関係のインストール
    log_info "依存関係をインストールしています..."
    npm install
    
    # 静的エクスポートビルド（APIとログインページを除外）
    log_info "静的エクスポートビルドを実行しています..."
    npm run build:static
    
    # outディレクトリの確認
    if [[ ! -d "out" ]]; then
        log_error "静的ビルドが失敗しました。outディレクトリが見つかりません。"
        exit 1
    fi
    
    # loginディレクトリが除外されているか確認
    if [[ -d "out/login" ]]; then
        log_warning "ログインディレクトリが静的ビルドに含まれています。手動で削除します..."
        rm -rf out/login
    fi
    
    log_success "静的ビルド完了"
    cd ..
}

# S3に再デプロイ
redeploy_to_s3() {
    log_info "S3に静的ファイルを再デプロイしています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    
    cd ../../../
    
    if [[ -z "$S3_BUCKET_NAME" ]]; then
        log_error "S3バケット名を取得できませんでした。"
        exit 1
    fi
    
    # S3に再アップロード
    aws s3 sync ./frontend/out s3://${S3_BUCKET_NAME} --delete
    
    log_success "S3再デプロイ完了"
}

# CloudFrontキャッシュ無効化
invalidate_cloudfront_cache() {
    log_info "CloudFrontキャッシュを無効化しています..."
    
    # すべてのパスを無効化
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id ${CLOUDFRONT_DISTRIBUTION_ID} \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    
    log_info "無効化ID: $INVALIDATION_ID"
    log_success "CloudFrontキャッシュ無効化を開始しました"
    
    log_info "完了まで待機する場合は以下のコマンドを実行してください:"
    echo "aws cloudfront wait invalidation-completed --distribution-id ${CLOUDFRONT_DISTRIBUTION_ID} --id ${INVALIDATION_ID}"
}

# App Runnerアプリケーションの再デプロイ
redeploy_app_runner() {
    log_info "App Runnerアプリケーションを再デプロイしています..."
    
    cd frontend
    
    # DockerイメージをECRにプッシュ
    log_info "DockerイメージをECRにプッシュしています..."
    npm run ecr:push:dev
    
    cd ..
    
    log_success "App Runnerアプリケーション再デプロイ完了"
    log_info "App Runnerの自動デプロイが開始されました（約3-5分で完了）"
}

# 修正内容の確認
verify_fix() {
    log_info "修正内容を確認しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    CLOUDFRONT_URL=$(terraform output -raw website_url 2>/dev/null || echo "")
    APP_RUNNER_URL=$(terraform output -raw app_runner_service_url 2>/dev/null || echo "")
    
    cd ../../../
    
    echo "=================================="
    echo "🔧 ログインページルーティング修正完了!"
    echo "=================================="
    echo "環境: ${ENVIRONMENT}"
    echo ""
    echo "📋 修正内容:"
    echo "✅ 静的ビルドからログインページを除外"
    echo "✅ S3から既存のログインページファイルを削除"
    echo "✅ CloudFrontキャッシュを無効化"
    echo "✅ App Runnerアプリケーションを再デプロイ"
    echo ""
    echo "🌐 テスト用URL:"
    echo "- ルートページ (S3): $CLOUDFRONT_URL"
    echo "- ログインページ (App Runner): $CLOUDFRONT_URL/login"
    echo "- API (App Runner): $CLOUDFRONT_URL/api/user-info"
    echo ""
    echo "📊 App Runner直接URL:"
    echo "- ログインページ: $APP_RUNNER_URL/login"
    echo "- API: $APP_RUNNER_URL/api/user-info"
    echo "=================================="
    
    log_warning "⚠️ 注意事項:"
    echo "- CloudFrontキャッシュの無効化は5-15分かかります"
    echo "- App Runnerの再デプロイは3-5分かかります"
    echo "- ブラウザのキャッシュもクリアしてテストしてください"
    echo ""
    echo "🧪 テストコマンド:"
    echo "./scripts/test-routing.sh ${ENVIRONMENT}"
}

# メイン処理
main() {
    log_info "ログインページルーティング修正を開始します"
    log_info "環境: ${ENVIRONMENT}"
    
    check_prerequisites
    get_cloudfront_info
    rebuild_static_site
    redeploy_to_s3
    invalidate_cloudfront_cache
    redeploy_app_runner
    verify_fix
    
    log_success "🎉 ログインページルーティング修正が完了しました!"
}

# スクリプト実行
main "$@"
