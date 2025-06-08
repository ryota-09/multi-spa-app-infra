#!/bin/bash

# Next.js Multi SPA App クリーンアップスクリプト
# 使用方法: ./scripts/cleanup.sh [environment]
# 例: ./scripts/cleanup.sh dev

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

# S3バケットの内容を削除
cleanup_s3_bucket() {
    log_info "S3バケットの内容を削除しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    # S3バケット名を取得
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    
    if [[ -n "$S3_BUCKET_NAME" ]]; then
        log_info "S3バケット '${S3_BUCKET_NAME}' の内容を削除しています..."
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive || log_warning "S3バケットの削除でエラーが発生しました"
        log_success "S3バケットの内容削除完了"
    else
        log_warning "S3バケット名を取得できませんでした"
    fi
    
    cd ../../../
}

# ECRイメージを削除
cleanup_ecr_images() {
    log_info "ECRイメージを削除しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    # ECRリポジトリURIを取得
    ECR_REPOSITORY_URI=$(terraform output -raw ecr_repository_uri 2>/dev/null || echo "")
    
    if [[ -n "$ECR_REPOSITORY_URI" ]]; then
        REPOSITORY_NAME=$(echo $ECR_REPOSITORY_URI | cut -d'/' -f2)
        log_info "ECRリポジトリ '${REPOSITORY_NAME}' のイメージを削除しています..."
        
        # 全イメージのダイジェストを取得して削除
        aws ecr list-images --repository-name ${REPOSITORY_NAME} --query 'imageIds[*]' --output json | \
        jq -r '.[] | select(.imageDigest) | .imageDigest' | \
        while read digest; do
            aws ecr batch-delete-image --repository-name ${REPOSITORY_NAME} --image-ids imageDigest=${digest} || true
        done
        
        log_success "ECRイメージ削除完了"
    else
        log_warning "ECRリポジトリURIを取得できませんでした"
    fi
    
    cd ../../../
}

# Terraformリソースを削除
destroy_infrastructure() {
    log_info "Terraformインフラを削除しています..."
    
    cd terraform/environments/${ENVIRONMENT}
    
    # terraform.tfvarsファイルの確認
    if [[ ! -f "terraform.tfvars" ]]; then
        log_error "terraform.tfvarsファイルが見つかりません"
        exit 1
    fi
    
    terraform plan -destroy
    
    echo -e "${RED}WARNING: 全てのインフラリソースが削除されます！${NC}"
    read -p "本当にインフラを削除しますか? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform destroy -auto-approve
        log_success "インフラ削除完了"
    else
        log_info "インフラ削除をキャンセルしました"
        exit 0
    fi
    
    cd ../../../
}

# ローカルファイルクリーンアップ
cleanup_local_files() {
    log_info "ローカルファイルをクリーンアップしています..."
    
    # Next.jsビルドファイル削除
    if [[ -d "out" ]]; then
        rm -rf out
        log_info "outディレクトリを削除しました"
    fi
    
    if [[ -d ".next" ]]; then
        rm -rf .next
        log_info ".nextディレクトリを削除しました"
    fi
    
    # Terraformファイル削除
    find terraform -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
    find terraform -name "*.tfstate*" -type f -delete 2>/dev/null || true
    find terraform -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true
    
    log_success "ローカルファイルクリーンアップ完了"
}

# メイン処理
main() {
    log_info "Next.js Multi SPA App クリーンアップを開始します"
    log_info "環境: ${ENVIRONMENT}"
    
    echo -e "${YELLOW}このスクリプトは以下の処理を実行します:${NC}"
    echo "1. S3バケットの内容削除"
    echo "2. ECRイメージの削除"
    echo "3. Terraformインフラの削除"
    echo "4. ローカルファイルのクリーンアップ"
    echo ""
    
    read -p "続行しますか? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "クリーンアップをキャンセルしました"
        exit 0
    fi
    
    cleanup_s3_bucket
    cleanup_ecr_images
    destroy_infrastructure
    cleanup_local_files
    
    log_success "🧹 全てのクリーンアップが完了しました!"
}

# スクリプト実行
main "$@"
