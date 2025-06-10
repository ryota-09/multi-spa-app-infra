#!/bin/bash

# CloudFront設定更新デプロイスクリプト
# 使用方法: ./scripts/update-cloudfront.sh [environment]

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
    for cmd in terraform aws; do
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

# Terraformでインフラ更新
update_infrastructure() {
    log_info "Terraformでインフラを更新しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    # Terraform初期化
    log_info "Terraformを初期化しています..."
    terraform init
    
    # プラン確認
    log_info "変更計画を確認しています..."
    terraform plan -out=tfplan
    
    # ユーザー確認
    echo ""
    log_warning "上記の変更を適用しますか？ (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "デプロイをキャンセルしました"
        cd ../../../
        exit 0
    fi
    
    # 適用
    log_info "変更を適用しています..."
    terraform apply tfplan
    
    # プランファイルを削除
    rm -f tfplan
    
    cd ../../../
    
    log_success "インフラ更新完了"
}

# 静的サイトの再デプロイ
redeploy_static_site() {
    log_info "静的サイトを再デプロイしています..."
    
    # 404.htmlファイルが含まれるように再ビルド
    ./scripts/deploy-frontend.sh ${ENVIRONMENT}
    
    log_success "静的サイト再デプロイ完了"
}

# デプロイ後テスト
run_post_deployment_tests() {
    log_info "デプロイ後テストを実行しています..."
    
    # テストスクリプトに実行権限を付与
    chmod +x scripts/test-routing.sh
    
    # ルーティングテストを実行
    ./scripts/test-routing.sh ${ENVIRONMENT}
    
    log_success "デプロイ後テスト完了"
}

# デプロイ情報表示
show_deployment_info() {
    log_info "デプロイ情報を表示しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    echo "=================================="
    echo "🚀 CloudFront設定更新完了!"
    echo "=================================="
    echo "環境: ${ENVIRONMENT}"
    echo ""
    echo "📋 更新内容:"
    echo "✅ /login* パスをApp Runnerに振り分け"
    echo "✅ カスタムエラーページ設定を修正"
    echo "✅ Cache Behavior順序を最適化"
    echo ""
    echo "🌐 ウェブサイトURL:"
    echo "$(terraform output -raw website_url)"
    echo ""
    echo "🔗 テスト用URL:"
    echo "- ルートページ: $(terraform output -raw website_url)"
    echo "- ログインページ: $(terraform output -raw website_url)/login"
    echo "- API: $(terraform output -raw website_url)/api/user-info"
    echo ""
    echo "📊 App Runner URL:"
    echo "$(terraform output -raw app_runner_service_url)"
    echo "=================================="
    
    cd ../../../
}

# メイン処理
main() {
    log_info "CloudFront設定更新デプロイを開始します"
    log_info "環境: ${ENVIRONMENT}"
    
    check_prerequisites
    update_infrastructure
    redeploy_static_site
    
    # CloudFrontの伝播を待機
    log_info "CloudFrontの設定伝播を待機しています（約2-3分）..."
    sleep 60
    
    run_post_deployment_tests
    show_deployment_info
    
    log_success "🎉 CloudFront設定更新デプロイが完了しました!"
    echo ""
    echo "💡 注意事項:"
    echo "- CloudFrontの設定変更は完全に伝播するまで5-15分かかる場合があります"
    echo "- ブラウザキャッシュをクリアしてテストしてください"
    echo "- 問題がある場合は './scripts/test-routing.sh ${ENVIRONMENT}' で再テストしてください"
}

# スクリプト実行
main "$@"
