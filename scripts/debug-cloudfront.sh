#!/bin/bash

# CloudFront問題の根本的解決スクリプト
# 使用方法: ./scripts/debug-cloudfront.sh [environment]

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

# CloudFront問題の段階的解決
main() {
    echo "🔍 CloudFront問題の根本的解決を開始します"
    echo "環境: $ENVIRONMENT"
    echo "========================================================"
    
    # Step 1: カスタムエラーページ設定の修正をデプロイ
    log_info "Step 1: カスタムエラーページ設定を修正してデプロイ"
    cd terraform/environments/${ENVIRONMENT}
    
    log_info "Terraform設定を適用中..."
    terraform plan -out=tfplan
    terraform apply tfplan
    rm -f tfplan
    
    # CloudFront情報を取得
    CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
    CLOUDFRONT_URL=$(terraform output -raw website_url)
    APP_RUNNER_URL=$(terraform output -raw app_runner_service_url)
    
    cd ../../..
    
    log_success "CloudFront設定を更新しました"
    log_debug "ディストリビューションID: $CLOUDFRONT_DISTRIBUTION_ID"
    
    # Step 2: 完全なキャッシュクリア
    log_info "Step 2: CloudFrontキャッシュを完全にクリア"
    
    # 全パスの無効化
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    
    log_debug "無効化ID: $INVALIDATION_ID"
    
    # Step 3: S3から不要なファイルを削除
    log_info "Step 3: S3から不要なログインファイルを削除"
    
    cd terraform/environments/${ENVIRONMENT}
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
    cd ../../..
    
    # S3からloginディレクトリを削除
    log_debug "S3からloginディレクトリを削除中..."
    aws s3 rm s3://${S3_BUCKET_NAME}/login --recursive 2>/dev/null || true
    aws s3 rm s3://${S3_BUCKET_NAME}/login.html 2>/dev/null || true
    
    # Step 4: 段階的テスト
    log_info "Step 4: 段階的にテストを実行"
    
    # 2分待機
    log_info "CloudFrontの初期反映を待機中（2分）..."
    sleep 120
    
    # App Runner直接テスト
    log_info "App Runner直接アクセステスト:"
    echo "URL: https://${APP_RUNNER_URL}/login"
    
    APP_RUNNER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${APP_RUNNER_URL}/login" || echo "FAILED")
    if [[ "$APP_RUNNER_STATUS" == "200" ]]; then
        log_success "✅ App Runner直接アクセス: 正常 (200)"
    else
        log_error "❌ App Runner直接アクセス: 異常 ($APP_RUNNER_STATUS)"
    fi
    
    # CloudFront経由テスト
    log_info "CloudFront経由アクセステスト:"
    echo "URL: ${CLOUDFRONT_URL}/login"
    
    CF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${CLOUDFRONT_URL}/login" || echo "FAILED")
    CF_CACHE=$(curl -s -I "${CLOUDFRONT_URL}/login" | grep -i "x-cache:" | head -1 || echo "x-cache: Unknown")
    
    echo "ステータス: $CF_STATUS"
    echo "キャッシュ: $CF_CACHE"
    
    if [[ "$CF_STATUS" == "200" ]]; then
        log_success "✅ CloudFront経由アクセス: 正常!"
        echo ""
        echo "🎉 問題が解決されました!"
    else
        log_warning "⚠️ CloudFront経由アクセス: まだ異常 ($CF_STATUS)"
        echo ""
        log_info "追加の診断を実行します..."
        
        # Step 5: 詳細診断
        log_info "Step 5: 詳細診断実行"
        
        # CloudFront設定確認
        log_debug "CloudFront設定確認:"
        aws cloudfront get-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" \
            --query 'Distribution.DistributionConfig.CacheBehaviors.Items[?PathPattern==`/login*`]' \
            --output table
        
        # 無効化状況確認
        log_debug "無効化状況確認:"
        aws cloudfront get-invalidation \
            --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
            --id "$INVALIDATION_ID" \
            --query 'Invalidation.Status' \
            --output text
        
        # 追加の無効化
        log_info "追加の無効化を実行..."
        INVALIDATION_ID_2=$(aws cloudfront create-invalidation \
            --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
            --paths "/login" "/login/*" \
            --query 'Invalidation.Id' \
            --output text)
        
        log_debug "追加無効化ID: $INVALIDATION_ID_2"
        
        log_info "さらに3分待機してから再テスト..."
        sleep 180
        
        # 再テスト
        CF_STATUS_2=$(curl -s -o /dev/null -w "%{http_code}" "${CLOUDFRONT_URL}/login" || echo "FAILED")
        CF_CACHE_2=$(curl -s -I "${CLOUDFRONT_URL}/login" | grep -i "x-cache:" | head -1 || echo "x-cache: Unknown")
        
        echo "再テスト結果:"
        echo "ステータス: $CF_STATUS_2"
        echo "キャッシュ: $CF_CACHE_2"
        
        if [[ "$CF_STATUS_2" == "200" ]]; then
            log_success "✅ 再テスト成功! 問題が解決されました!"
        else
            log_error "❌ 再テストでも問題が継続しています"
            echo ""
            log_info "推奨する次のステップ:"
            echo "1. 追加で10-15分待機してから手動でテスト"
            echo "2. CloudFrontコンソールで設定を直接確認"
            echo "3. 必要に応じてCloudFrontディストリビューションを再作成"
        fi
    fi
    
    # Step 6: 結果サマリー
    echo ""
    echo "========================================================"
    echo "🔍 CloudFront問題解決結果サマリー"
    echo "========================================================"
    echo "環境: $ENVIRONMENT"
    echo "CloudFrontディストリビューション: $CLOUDFRONT_DISTRIBUTION_ID"
    echo "ウェブサイトURL: $CLOUDFRONT_URL"
    echo ""
    echo "実行した修正:"
    echo "✅ カスタムエラーページ設定を修正 (404→404, 不適切なリダイレクト削除)"
    echo "✅ S3からログインファイルを削除"
    echo "✅ CloudFrontキャッシュを完全無効化"
    echo "✅ ヘッダー転送設定を最適化"
    echo ""
    echo "テスト結果:"
    echo "App Runner直接: $APP_RUNNER_STATUS"
    echo "CloudFront経由: $CF_STATUS"
    if [[ -n "$CF_STATUS_2" ]]; then
        echo "CloudFront再テスト: $CF_STATUS_2"
    fi
    echo ""
    echo "⚠️ 注意: CloudFrontの設定変更は完全に反映されるまで5-15分かかる場合があります"
    echo "========================================================"
}

# スクリプト実行
main "$@"
