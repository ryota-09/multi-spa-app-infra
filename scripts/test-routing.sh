#!/bin/bash

# CloudFrontルーティングテストスクリプト
# 使用方法: ./scripts/test-routing.sh [environment]

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

# Terraform出力値を取得
get_urls() {
    log_info "Terraform出力値を取得しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    CLOUDFRONT_URL=$(terraform output -raw website_url 2>/dev/null || echo "")
    APP_RUNNER_URL=$(terraform output -raw app_runner_service_url 2>/dev/null || echo "")
    
    cd ../../../
    
    if [[ -z "$CLOUDFRONT_URL" ]] || [[ -z "$APP_RUNNER_URL" ]]; then
        log_error "Terraform出力値を取得できませんでした。インフラがデプロイされているか確認してください。"
        exit 1
    fi
    
    log_success "CloudFront URL: $CLOUDFRONT_URL"
    log_success "App Runner URL: $APP_RUNNER_URL"
}

# URLのテスト
test_url() {
    local url=$1
    local description=$2
    local expected_string=$3
    
    log_info "テスト中: $description"
    log_info "URL: $url"
    
    # HTTPステータスコードを取得
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
    
    if [[ "$status_code" == "200" ]]; then
        log_success "✅ ステータスコード: $status_code"
        
        # 期待する文字列が含まれているかチェック
        if [[ -n "$expected_string" ]]; then
            local content=$(curl -s "$url" || echo "")
            if echo "$content" | grep -q "$expected_string"; then
                log_success "✅ 期待する内容が含まれています: $expected_string"
            else
                log_warning "⚠️ 期待する内容が見つかりません: $expected_string"
            fi
        fi
    else
        log_error "❌ ステータスコード: $status_code"
    fi
    
    echo ""
}

# ルーティングテストの実行
run_routing_tests() {
    log_info "CloudFrontルーティングテストを開始します..."
    echo "=================================="
    
    # ルートページテスト（S3 → 静的コンテンツ）
    test_url "$CLOUDFRONT_URL" "ルートページ（S3静的配信）" "ECサイトサンプル"
    
    # APIテスト（CloudFront → App Runner）
    test_url "${CLOUDFRONT_URL}/api/user-info" "API Route（App Runner動的配信）" "田中太郎"
    
    # ログインページテスト（CloudFront → App Runner）
    test_url "${CLOUDFRONT_URL}/login" "ログインページ（App Runner動的配信）" "ログイン"
    
    # 商品ページテスト（S3 → 静的コンテンツ）
    test_url "${CLOUDFRONT_URL}/products/sample" "商品ページ（S3静的配信）" "商品"
    
    # App Runnerの直接テスト
    log_info "App Runnerの直接アクセステスト..."
    test_url "${APP_RUNNER_URL}/login" "App Runner直接アクセス - ログインページ" "ログイン"
    test_url "${APP_RUNNER_URL}/api/user-info" "App Runner直接アクセス - API" "田中太郎"
    
    echo "=================================="
    log_info "ルーティングテスト完了"
}

# ヘッダー情報の表示
show_headers() {
    log_info "レスポンスヘッダー情報を表示します..."
    echo "=================================="
    
    echo "🌐 CloudFront経由 - ルートページ (静的):"
    curl -s -I "$CLOUDFRONT_URL" | head -10
    echo ""
    
    echo "🌐 CloudFront経由 - API (動的):"
    curl -s -I "${CLOUDFRONT_URL}/api/user-info" | head -10
    echo ""
    
    echo "🌐 CloudFront経由 - ログインページ (動的):"
    curl -s -I "${CLOUDFRONT_URL}/login" | head -10
    echo ""
    
    echo "=================================="
}

# メイン処理
main() {
    log_info "CloudFrontルーティングテストを開始します"
    log_info "環境: ${ENVIRONMENT}"
    
    get_urls
    run_routing_tests
    show_headers
    
    log_success "🎉 すべてのテストが完了しました!"
    echo ""
    echo "📋 確認ポイント:"
    echo "- ルートページ(/)がS3から配信されているか"
    echo "- /loginがApp Runnerから配信されているか"
    echo "- /api/*がApp Runnerから配信されているか"
    echo "- 各URLで適切なキャッシュヘッダーが設定されているか"
}

# スクリプト実行
main "$@"
