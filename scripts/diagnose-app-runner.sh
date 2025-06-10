#!/bin/bash

# App Runnerオリジン診断スクリプト
# 使用方法: ./scripts/diagnose-app-runner.sh [environment]

set -e

# 変数設定
ENVIRONMENT=${1:-dev}

# 色付きログ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $1"
}

# App Runnerの詳細診断
main() {
    echo "🔍 App Runnerオリジン診断を開始します"
    echo "環境: $ENVIRONMENT"
    echo "========================================================"
    
    # Step 1: Terraform出力から情報取得
    log_info "Step 1: 現在の設定情報を取得"
    cd terraform/environments/${ENVIRONMENT}
    
    CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
    CLOUDFRONT_URL=$(terraform output -raw website_url)
    APP_RUNNER_URL=$(terraform output -raw app_runner_service_url)
    
    cd ../../..
    
    echo "CloudFront Distribution ID: $CLOUDFRONT_DISTRIBUTION_ID"
    echo "CloudFront URL: $CLOUDFRONT_URL"
    echo "App Runner URL: $APP_RUNNER_URL"
    
    # Step 2: CloudFrontのオリジン設定確認
    log_info "Step 2: CloudFrontのオリジン設定を確認"
    
    echo "=== CloudFrontオリジン情報 ==="
    aws cloudfront get-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --query 'Distribution.DistributionConfig.Origins.Items[?Id==`AppRunner-multi-spa-app-dev`]' \
        --output table
    
    # Step 3: App Runnerサービス状態確認
    log_info "Step 3: App Runnerサービス状態を確認"
    
    # App RunnerサービスARNを取得
    APP_RUNNER_SERVICE_ARN=$(aws apprunner list-services \
        --query "ServiceSummaryList[?ServiceName=='multi-spa-app-${ENVIRONMENT}'].ServiceArn" \
        --output text)
    
    if [[ -n "$APP_RUNNER_SERVICE_ARN" ]]; then
        log_debug "App RunnerサービスARN: $APP_RUNNER_SERVICE_ARN"
        
        echo "=== App Runnerサービス詳細 ==="
        aws apprunner describe-service --service-arn "$APP_RUNNER_SERVICE_ARN" \
            --query 'Service.{Status:Status,ServiceUrl:ServiceUrl,SourceConfiguration:SourceConfiguration.ImageRepository}' \
            --output table
    else
        log_error "App Runnerサービスが見つかりません"
    fi
    
    # Step 4: 直接テスト
    log_info "Step 4: 直接アクセステスト"
    
    echo "=== App Runner直接テスト ==="
    echo "URL: https://${APP_RUNNER_URL}/login"
    
    APP_RUNNER_RESPONSE=$(curl -s -v "https://${APP_RUNNER_URL}/login" 2>&1)
    APP_RUNNER_STATUS=$(echo "$APP_RUNNER_RESPONSE" | grep "< HTTP" | head -1 || echo "HTTP/1.1 UNKNOWN Unknown")
    
    echo "レスポンス: $APP_RUNNER_STATUS"
    
    # レスポンスヘッダーを確認
    echo ""
    echo "=== App Runnerレスポンスヘッダー ==="
    curl -s -I "https://${APP_RUNNER_URL}/login" || echo "Failed to get headers"
    
    # Step 5: CloudFront経由テスト
    log_info "Step 5: CloudFront経由テスト"
    
    echo "=== CloudFront経由テスト ==="
    echo "URL: ${CLOUDFRONT_URL}/login"
    
    CF_RESPONSE=$(curl -s -v "${CLOUDFRONT_URL}/login" 2>&1)
    CF_STATUS=$(echo "$CF_RESPONSE" | grep "< HTTP" | head -1 || echo "HTTP/1.1 UNKNOWN Unknown")
    
    echo "レスポンス: $CF_STATUS"
    
    # CloudFrontヘッダーを確認
    echo ""
    echo "=== CloudFrontレスポンスヘッダー ==="
    curl -s -I "${CLOUDFRONT_URL}/login" || echo "Failed to get headers"
    
    # Step 6: オリジンヘルスチェック
    log_info "Step 6: オリジンヘルスチェック"
    
    # CloudFrontのオリジンドメイン名を直接確認
    ORIGIN_DOMAIN=$(aws cloudfront get-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --query 'Distribution.DistributionConfig.Origins.Items[?Id==`AppRunner-multi-spa-app-dev`].DomainName' \
        --output text)
    
    echo "CloudFront設定のオリジンドメイン: $ORIGIN_DOMAIN"
    echo "App RunnerのURL: $APP_RUNNER_URL"
    
    # ドメイン名の一致確認
    if [[ "$ORIGIN_DOMAIN" == "${APP_RUNNER_URL/https:\/\//}" ]]; then
        log_success "✅ オリジンドメイン名は一致しています"
    else
        log_error "❌ オリジンドメイン名が一致していません!"
        echo "期待値: ${APP_RUNNER_URL/https:\/\//}"
        echo "実際値: $ORIGIN_DOMAIN"
    fi
    
    # Step 7: オリジンの直接テスト
    log_info "Step 7: オリジンドメインの直接テスト"
    
    if [[ -n "$ORIGIN_DOMAIN" ]]; then
        echo "オリジンドメインへの直接アクセステスト:"
        echo "URL: https://${ORIGIN_DOMAIN}/login"
        
        ORIGIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${ORIGIN_DOMAIN}/login" 2>/dev/null || echo "FAILED")
        echo "ステータス: $ORIGIN_STATUS"
        
        if [[ "$ORIGIN_STATUS" == "200" ]]; then
            log_success "✅ オリジンドメインは正常に応答しています"
        else
            log_error "❌ オリジンドメインが応答していません ($ORIGIN_STATUS)"
        fi
    fi
    
    # Step 8: 診断結果と推奨事項
    echo ""
    echo "========================================================"
    echo "🔍 診断結果サマリー"
    echo "========================================================"
    
    echo "App Runner直接: $(echo "$APP_RUNNER_STATUS" | cut -d' ' -f2 || echo "UNKNOWN")"
    echo "CloudFront経由: $(echo "$CF_STATUS" | cut -d' ' -f2 || echo "UNKNOWN")"
    echo "オリジンドメイン直接: $ORIGIN_STATUS"
    
    echo ""
    echo "推奨事項:"
    
    if [[ "$ORIGIN_DOMAIN" != "${APP_RUNNER_URL/https:\/\//}" ]]; then
        log_error "1. ❌ オリジンドメイン名の不一致が検出されました"
        echo "   - Terraformの設定を確認してください"
        echo "   - terraform apply を再実行してください"
    fi
    
    if [[ "$ORIGIN_STATUS" != "200" ]]; then
        log_error "2. ❌ オリジンが応答していません"
        echo "   - App Runnerサービスの状態を確認してください"
        echo "   - ECRイメージが最新かどうか確認してください"
        echo "   - App Runnerのログを確認してください"
    fi
    
    CF_STATUS_CODE=$(echo "$CF_STATUS" | cut -d' ' -f2 || echo "UNKNOWN")
    if [[ "$CF_STATUS_CODE" != "200" ]]; then
        log_error "3. ❌ CloudFront経由でアクセスできません"
        echo "   - キャッシュ無効化を実行してください"
        echo "   - CloudFrontの設定を再確認してください"
    fi
    
    echo ""
    echo "次のステップ:"
    echo "1. 問題が見つかった場合は該当の修正を実行"
    echo "2. 修正後は ./scripts/debug-cloudfront.sh で再テスト"
    echo "3. 問題が継続する場合はAWSコンソールで詳細確認"
    echo "========================================================"
}

# スクリプト実行
main "$@"
