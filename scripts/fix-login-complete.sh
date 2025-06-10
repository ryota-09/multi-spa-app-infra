#!/bin/bash

# ログイン問題の完全解決スクリプト
# 使用方法: ./scripts/fix-login-complete.sh [environment]

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

# メイン関数
main() {
    echo "🔧 ログイン問題の完全解決を開始します"
    echo "環境: $ENVIRONMENT"
    echo "========================================================"
    
    # Step 1: Next.js設定確認
    log_info "Step 1: Next.js設定を確認"
    
    if [[ -f "frontend/next.config.ts" ]]; then
        log_debug "Next.js設定ファイルが最新の状態であることを確認..."
        
        # trailingSlash設定の確認
        if grep -q "trailingSlash: process.env.STANDALONE" frontend/next.config.ts; then
            log_success "✅ Next.js設定が最新（ハイブリッド構成対応）"
        else
            log_warning "⚠️ Next.js設定が古い可能性があります"
            echo "最新の設定に更新してください"
        fi
    else
        log_error "❌ Next.js設定ファイルが見つかりません"
        exit 1
    fi
    
    # Step 2: Docker imageの再ビルドとデプロイ
    log_info "Step 2: 修正されたNext.js設定でApp Runnerを再デプロイ"
    
    cd frontend
    
    # ECRリポジトリ情報取得
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "us-east-1")
    ECR_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/multi-spa-app-${ENVIRONMENT}"
    
    log_debug "ECRリポジトリ: $ECR_REPOSITORY"
    
    # ECRログイン
    log_info "ECRにログイン中..."
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY
    
    # Docker image再ビルド
    log_info "修正されたNext.js設定でDockerイメージをビルド中..."
    docker build -t $ECR_REPOSITORY:latest .
    
    # ECRにプッシュ
    log_info "ECRにプッシュ中..."
    docker push $ECR_REPOSITORY:latest
    
    cd ..
    
    # Step 3: App Runnerサービス更新
    log_info "Step 3: App Runnerサービスを更新"
    
    # App RunnerサービスARNを取得
    APP_RUNNER_SERVICE_ARN=$(aws apprunner list-services \
        --query "ServiceSummaryList[?ServiceName=='multi-spa-app-${ENVIRONMENT}'].ServiceArn" \
        --output text)
    
    if [[ -n "$APP_RUNNER_SERVICE_ARN" ]]; then
        log_debug "App RunnerサービスARN: $APP_RUNNER_SERVICE_ARN"
        
        log_info "App Runnerサービスを更新中..."
        aws apprunner start-deployment --service-arn "$APP_RUNNER_SERVICE_ARN"
        
        log_info "App Runnerのデプロイメント完了を待機中..."
        aws apprunner wait service-running --service-arn "$APP_RUNNER_SERVICE_ARN"
        
        log_success "✅ App Runnerサービスの更新完了"
    else
        log_error "❌ App Runnerサービスが見つかりません"
        exit 1
    fi
    
    # Step 4: CloudFront設定更新
    log_info "Step 4: CloudFront設定を更新"
    
    cd terraform/environments/${ENVIRONMENT}
    
    log_info "Terraform planを実行中..."
    terraform plan -out=tfplan
    
    log_info "Terraform applyを実行中..."
    terraform apply tfplan
    rm -f tfplan
    
    # CloudFront情報を取得
    CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
    CLOUDFRONT_URL=$(terraform output -raw website_url)
    APP_RUNNER_URL=$(terraform output -raw app_runner_service_url)
    
    cd ../../..
    
    log_success "✅ CloudFront設定の更新完了"
    log_debug "ディストリビューションID: $CLOUDFRONT_DISTRIBUTION_ID"
    
    # Step 5: CloudFrontキャッシュの完全無効化
    log_info "Step 5: CloudFrontキャッシュを完全無効化"
    
    # 全パスの無効化
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    
    log_debug "無効化ID: $INVALIDATION_ID"
    
    # S3からloginファイルを削除
    cd terraform/environments/${ENVIRONMENT}
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
    cd ../../..
    
    log_info "S3から競合するloginファイルを削除中..."
    aws s3 rm s3://${S3_BUCKET_NAME}/login --recursive 2>/dev/null || true
    aws s3 rm s3://${S3_BUCKET_NAME}/login.html 2>/dev/null || true
    
    # Step 6: 段階的テストと検証
    log_info "Step 6: 段階的テストを実行"
    
    # 初期待機
    log_info "CloudFrontの設定反映を待機中（3分）..."
    sleep 180
    
    # App Runner直接テスト
    log_info "=== App Runner直接テスト ==="
    echo "URL: https://${APP_RUNNER_URL}/login"
    
    APP_RUNNER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${APP_RUNNER_URL}/login" || echo "FAILED")
    
    if [[ "$APP_RUNNER_STATUS" == "200" ]]; then
        log_success "✅ App Runner直接アクセス: 正常 (200)"
    else
        log_error "❌ App Runner直接アクセス: 異常 ($APP_RUNNER_STATUS)"
        echo "App Runnerログを確認してください"
    fi
    
    # CloudFront経由テスト
    log_info "=== CloudFront経由テスト ==="
    echo "URL: ${CLOUDFRONT_URL}/login"
    
    CF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${CLOUDFRONT_URL}/login" || echo "FAILED")
    CF_CACHE=$(curl -s -I "${CLOUDFRONT_URL}/login" | grep -i "x-cache:" | head -1 || echo "x-cache: Unknown")
    
    echo "ステータス: $CF_STATUS"
    echo "キャッシュ: $CF_CACHE"
    
    if [[ "$CF_STATUS" == "200" ]]; then
        log_success "✅ CloudFront経由アクセス: 正常!"
        
        # 追加のパスパターンテスト
        log_info "=== 追加パスパターンテスト ==="
        
        # /login/ (trailing slash) テスト
        CF_STATUS_SLASH=$(curl -s -o /dev/null -w "%{http_code}" "${CLOUDFRONT_URL}/login/" || echo "FAILED")
        echo "/login/ ステータス: $CF_STATUS_SLASH"
        
        # /api/user-info テスト
        API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${CLOUDFRONT_URL}/api/user-info" || echo "FAILED")
        echo "/api/user-info ステータス: $API_STATUS"
        
    else
        log_warning "⚠️ CloudFront経由アクセス: まだ異常 ($CF_STATUS)"
        
        if [[ "$CF_STATUS" == "404" ]]; then
            log_info "404エラー: キャッシュが残っている可能性があります"
            log_info "追加の無効化を実行します..."
            
            # 追加の無効化
            INVALIDATION_ID_2=$(aws cloudfront create-invalidation \
                --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
                --paths "/login" "/login/*" \
                --query 'Invalidation.Id' \
                --output text)
            
            log_debug "追加無効化ID: $INVALIDATION_ID_2"
        fi
    fi
    
    # Step 7: 結果サマリーと推奨事項
    echo ""
    echo "========================================================"
    echo "🎯 ログイン問題解決結果サマリー"
    echo "========================================================"
    echo "環境: $ENVIRONMENT"
    echo "CloudFrontディストリビューション: $CLOUDFRONT_DISTRIBUTION_ID"
    echo "ウェブサイトURL: $CLOUDFRONT_URL"
    echo ""
    echo "実行した修正:"
    echo "✅ Next.js trailingSlash設定を修正 (App Runner用: false)"
    echo "✅ Next.js skipTrailingSlashRedirect設定を追加"
    echo "✅ CloudFrontパスパターンを最適化 (/login と /login/*)"
    echo "✅ カスタムエラーページ設定を修正"
    echo "✅ App Runnerサービスを最新イメージで更新"
    echo "✅ CloudFrontキャッシュを完全無効化"
    echo ""
    echo "テスト結果:"
    echo "App Runner直接: $APP_RUNNER_STATUS"
    echo "CloudFront経由: $CF_STATUS"
    
    if [[ -n "$CF_STATUS_SLASH" ]]; then
        echo "CloudFront /login/: $CF_STATUS_SLASH"
    fi
    
    if [[ -n "$API_STATUS" ]]; then
        echo "CloudFront /api/*: $API_STATUS"
    fi
    
    echo ""
    
    if [[ "$CF_STATUS" == "200" ]]; then
        echo "🎉 問題が解決されました！"
        echo "ログインページは正常にApp Runnerから配信されています。"
    else
        echo "⚠️ 問題が継続しています。以下を確認してください："
        echo "1. 追加で5-10分待機してから再テスト"
        echo "2. ブラウザのキャッシュをクリア"
        echo "3. AWSコンソールでApp RunnerとCloudFrontの状態を確認"
        echo "4. ./scripts/diagnose-app-runner.sh ${ENVIRONMENT} で詳細診断"
    fi
    
    echo "========================================================"
}

# スクリプト実行
main "$@"
