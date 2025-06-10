#!/bin/bash

# Next.js Multi SPA App デプロイスクリプト
# 使用方法: ./scripts/deploy.sh [environment] [image_tag] [options]
# 例: ./scripts/deploy.sh dev v1.0.0
# オプション: --skip-infrastructure, --skip-docker, --skip-static, --help

set -e

# デフォルト変数設定
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}
PROJECT_NAME="multi-spa-app"
AWS_REGION="ap-northeast-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# オプション変数
SKIP_INFRASTRUCTURE=false
SKIP_DOCKER=false
SKIP_STATIC=false
FORCE_YES=false
VERBOSE=false

# 色付きログ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ヘルプ表示
show_help() {
    echo "Next.js Multi SPA App デプロイスクリプト"
    echo ""
    echo "使用方法: $0 [environment] [image_tag] [options]"
    echo ""
    echo "引数:"
    echo "  environment   デプロイ環境 (デフォルト: dev)"
    echo "  image_tag     Dockerイメージタグ (デフォルト: latest)"
    echo ""
    echo "オプション:"
    echo "  --skip-infrastructure  インフラストラクチャのデプロイをスキップ"
    echo "  --skip-docker          Dockerイメージのビルド・プッシュをスキップ"
    echo "  --skip-static          静的ファイルのデプロイをスキップ"
    echo "  --force-yes            確認プロンプトをスキップ"
    echo "  --verbose              詳細な出力を表示"
    echo "  --help                 このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 dev v1.0.0"
    echo "  $0 prod latest --skip-infrastructure"
    echo "  $0 dev v2.0.0 --force-yes --verbose"
}

# 引数解析
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-infrastructure)
                SKIP_INFRASTRUCTURE=true
                shift
                ;;
            --skip-docker)
                SKIP_DOCKER=true
                shift
                ;;
            --skip-static)
                SKIP_STATIC=true
                shift
                ;;
            --force-yes)
                FORCE_YES=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
}

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
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# エラーハンドリング
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "デプロイ中にエラーが発生しました (終了コード: $exit_code)"
        log_info "ログを確認してエラーを修正してください"
    fi
    exit $exit_code
}

trap cleanup EXIT

# 確認プロンプト
confirm() {
    local message="$1"
    if [[ "$FORCE_YES" == "true" ]]; then
        log_debug "Force mode enabled, skipping confirmation for: $message"
        return 0
    fi
    
    read -p "$message (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# 前提条件チェック
check_prerequisites() {
    log_step "前提条件をチェックしています..."
    
    # 必要なコマンドの確認
    local missing_commands=()
    for cmd in aws docker terraform npm jq; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "以下のコマンドがインストールされていません: ${missing_commands[*]}"
        log_info "必要なツールをインストールしてから再実行してください"
        exit 1
    fi
    
    # AWS認証確認
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証が設定されていません"
        log_info "aws configureまたはAWSクレデンシャルを設定してください"
        exit 1
    fi
    
    # Docker デーモン確認
    if ! docker info &> /dev/null; then
        log_error "Dockerデーモンが起動していません"
        log_info "Docker Desktopを起動してから再実行してください"
        exit 1
    fi
    
    # ワーキングディレクトリ確認
    if [[ ! -d "$ROOT_DIR/terraform/environments/$ENVIRONMENT" ]]; then
        log_error "環境ディレクトリが見つかりません: $ROOT_DIR/terraform/environments/$ENVIRONMENT"
        exit 1
    fi
    
    log_debug "AWS Account: $(aws sts get-caller-identity --query Account --output text)"
    log_debug "AWS Region: $AWS_REGION"
    log_debug "Root Directory: $ROOT_DIR"
    log_success "前提条件チェック完了"
}

# Terraformインフラデプロイ
deploy_infrastructure() {
    log_step "Terraformインフラをデプロイしています..."
    
    cd "$ROOT_DIR/terraform/environments/$ENVIRONMENT"
    
    # terraform.tfvarsファイルの確認
    if [[ ! -f "terraform.tfvars" ]]; then
        log_warning "terraform.tfvarsファイルが見つかりません"
        if [[ -f "terraform.tfvars.example" ]]; then
            log_info "terraform.tfvars.exampleをコピーしています..."
            cp terraform.tfvars.example terraform.tfvars
            log_warning "terraform.tfvarsファイルを編集してから再実行してください"
        else
            log_error "terraform.tfvars.exampleファイルも見つかりません"
        fi
        exit 1
    fi
    
    # Terraformの初期化
    log_info "Terraform初期化中..."
    if [[ "$VERBOSE" == "true" ]]; then
        terraform init
    else
        terraform init > /dev/null 2>&1
    fi
    
    # プラン表示
    log_info "Terraformプランを作成中..."
    terraform plan -var="ecr_image_tag=$IMAGE_TAG" -out=tfplan
    
    # デプロイ確認
    if confirm "インフラをデプロイしますか?"; then
        log_info "インフラをデプロイ中..."
        terraform apply tfplan
        rm -f tfplan
        log_success "インフラデプロイ完了"
    else
        log_info "インフラデプロイをキャンセルしました"
        rm -f tfplan
        exit 0
    fi
    
    cd "$ROOT_DIR"
}

# ECRリポジトリURIを取得
get_ecr_repository() {
    log_step "ECRリポジトリ情報を取得しています..."
    
    cd "$ROOT_DIR/terraform/environments/$ENVIRONMENT"
    ECR_REPOSITORY_URI=$(terraform output -raw ecr_repository_uri 2>/dev/null || echo "")
    cd "$ROOT_DIR"
    
    if [[ -z "$ECR_REPOSITORY_URI" ]]; then
        log_error "ECRリポジトリURIを取得できませんでした"
        log_info "インフラストラクチャが正しくデプロイされているか確認してください"
        exit 1
    fi
    
    log_debug "ECRリポジトリURI: $ECR_REPOSITORY_URI"
    log_success "ECRリポジトリ情報取得完了"
}

# Dockerイメージビルド・プッシュ
build_and_push_image() {
    log_step "Dockerイメージをビルド・プッシュしています..."
    
    cd "$ROOT_DIR/frontend"
    
    # ECRログイン
    log_info "ECRにログイン中..."
    if ! aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPOSITORY_URI" 2>/dev/null; then
        log_error "ECRログインに失敗しました"
        exit 1
    fi
    
    # 既存イメージの確認
    log_info "既存のDockerイメージを確認中..."
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$PROJECT_NAME:$IMAGE_TAG"; then
        if confirm "既存のイメージ $PROJECT_NAME:$IMAGE_TAG が見つかりました。再ビルドしますか?"; then
            docker rmi "$PROJECT_NAME:$IMAGE_TAG" 2>/dev/null || true
        else
            log_info "既存のイメージを使用します"
        fi
    fi
    
    # Dockerイメージビルド
    log_info "Dockerイメージをビルド中..."
    local build_args=""
    if [[ "$VERBOSE" != "true" ]]; then
        build_args="--quiet"
    fi
    
    docker build --platform linux/amd64 $build_args -t "$PROJECT_NAME:$IMAGE_TAG" .
    
    # タグ付け
    log_debug "イメージにタグを付けています..."
    docker tag "$PROJECT_NAME:$IMAGE_TAG" "$ECR_REPOSITORY_URI:$IMAGE_TAG"
    
    # プッシュ
    log_info "ECRにプッシュ中..."
    if [[ "$VERBOSE" == "true" ]]; then
        docker push "$ECR_REPOSITORY_URI:$IMAGE_TAG"
    else
        docker push "$ECR_REPOSITORY_URI:$IMAGE_TAG" | grep -E "(Pushed|exists|digest:)" || true
    fi
    
    # ローカルイメージのクリーンアップ
    log_debug "ローカルイメージをクリーンアップ中..."
    docker rmi "$PROJECT_NAME:$IMAGE_TAG" 2>/dev/null || true
    
    cd "$ROOT_DIR"
    log_success "Dockerイメージのビルド・プッシュ完了"
}

# 静的ファイルビルド・アップロード
deploy_static_files() {
    log_step "静的ファイルをビルド・アップロードしています..."
    
    cd "$ROOT_DIR/frontend"
    
    # Node.js依存関係の確認
    if [[ ! -d "node_modules" ]] || [[ "package.json" -nt "node_modules" ]]; then
        log_info "依存関係をインストール中..."
        if [[ "$VERBOSE" == "true" ]]; then
            npm install
        else
            npm install --silent
        fi
    else
        log_debug "依存関係は最新です"
    fi
    
    # Next.js静的ビルド（ログインページとAPIを除外）
    log_info "Next.jsアプリケーションをビルド中（ログインページとAPIを除外）..."
    npm run build:static
    
    # 出力ディレクトリの確認
    if [[ ! -d "out" ]]; then
        log_error "静的ビルドが失敗しました。outディレクトリが見つかりません。"
        exit 1
    fi
    
    # loginディレクトリが除外されているか確認（念のため）
    if [[ -d "out/login" ]]; then
        log_warning "ログインディレクトリが静的ビルドに含まれています。手動で削除します..."
        rm -rf out/login
        log_debug "ログインディレクトリを削除しました"
    fi
    
    # apiディレクトリが除外されているか確認（念のため）
    if [[ -d "out/api" ]]; then
        log_warning "APIディレクトリが静的ビルドに含まれています。手動で削除します..."
        rm -rf out/api
        log_debug "APIディレクトリを削除しました"
    fi
    
    # S3バケット名とCloudFrontディストリビューションIDを取得
    cd "$ROOT_DIR/terraform/environments/$ENVIRONMENT"
    local s3_bucket_name
    local cloudfront_distribution_id
    s3_bucket_name=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    cloudfront_distribution_id=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
    cd "$ROOT_DIR/frontend"
    
    if [[ -z "$s3_bucket_name" ]]; then
        log_error "S3バケット名を取得できませんでした"
        exit 1
    fi
    
    # S3にアップロード
    log_info "S3にアップロード中..."
    aws s3 sync ./out "s3://$s3_bucket_name" --delete
    
    # CloudFrontキャッシュクリア
    if [[ -n "$cloudfront_distribution_id" ]]; then
        log_info "CloudFrontキャッシュをクリア中（静的アセットのみ）..."
        local invalidation_id
        invalidation_id=$(aws cloudfront create-invalidation \
            --distribution-id "$cloudfront_distribution_id" \
            --paths "/_next/static/*" "/favicon.ico" "/index.html" "/*.svg" "/images/*" \
            --query 'Invalidation.Id' \
            --output text)
        log_debug "無効化ID: $invalidation_id"
        
        if confirm "CloudFrontキャッシュクリアの完了を待機しますか?"; then
            log_info "キャッシュクリアの完了を待機中..."
            aws cloudfront wait invalidation-completed \
                --distribution-id "$cloudfront_distribution_id" \
                --id "$invalidation_id"
            log_success "CloudFrontキャッシュクリア完了"
        fi
    else
        log_warning "CloudFrontディストリビューションIDが見つかりません。キャッシュクリアをスキップします。"
    fi
    
    # 一時ファイルクリーンアップ
    log_debug "一時ファイルをクリーンアップ中..."
    rm -rf out
    
    cd "$ROOT_DIR"
    log_success "静的ファイルのデプロイ完了"
}

# デプロイ情報表示
show_deployment_info() {
    log_step "デプロイ情報を表示しています..."
    
    cd "$ROOT_DIR/terraform/environments/$ENVIRONMENT"
    
    echo ""
    echo "=================================="
    echo "🚀 デプロイ完了!"
    echo "=================================="
    echo "環境: $ENVIRONMENT"
    echo "イメージタグ: $IMAGE_TAG"
    echo "デプロイ時刻: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "📋 リソース情報:"
    
    # エラーハンドリング付きでTerraform出力を取得
    local ecr_repo app_runner_url s3_bucket cf_id website_url
    ecr_repo=$(terraform output -raw ecr_repository_uri 2>/dev/null || echo "N/A")
    app_runner_url=$(terraform output -raw app_runner_service_url 2>/dev/null || echo "N/A")
    s3_bucket=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "N/A")
    cf_id=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "N/A")
    website_url=$(terraform output -raw website_url 2>/dev/null || echo "N/A")
    
    echo "ECRリポジトリ: $ecr_repo"
    echo "App Runner URL: https://$app_runner_url"
    echo "S3バケット: $s3_bucket"
    echo "CloudFront ID: $cf_id"
    echo ""
    echo "🌐 ウェブサイトURL:"
    echo "$website_url"
    echo ""
    echo "🔗 テスト用URL:"
    echo "- ルートページ (S3静的): $website_url"
    echo "- ログインページ (App Runner動的): $website_url/login"
    echo "- API (App Runner動的): $website_url/api/user-info"
    echo ""
    echo "📊 ハイブリッド構成:"
    echo "✅ CloudFrontルーティング:"
    echo "  ├── /login* → App Runner (動的・キャッシュ無効)"
    echo "  ├── /api/* → App Runner (動的・キャッシュ無効)"
    echo "  └── /* → S3 (静的・長期キャッシュ)"
    echo ""
    echo "📊 デプロイ統計:"
    if [[ "$SKIP_INFRASTRUCTURE" == "false" ]]; then
        echo "✅ インフラストラクチャ: デプロイ済み"
    else
        echo "⏭️  インフラストラクチャ: スキップ"
    fi
    if [[ "$SKIP_DOCKER" == "false" ]]; then
        echo "✅ Dockerイメージ: ビルド・プッシュ済み"
    else
        echo "⏭️  Dockerイメージ: スキップ"
    fi
    if [[ "$SKIP_STATIC" == "false" ]]; then
        echo "✅ 静的ファイル: デプロイ済み (ログインページ・API除外)"
    else
        echo "⏭️  静的ファイル: スキップ"
    fi
    echo ""
    echo "🧪 テストコマンド:"
    echo "./scripts/test-routing.sh $ENVIRONMENT"
    echo "=================================="
    
    cd "$ROOT_DIR"
}

# メイン処理
main() {
    # 引数解析
    parse_arguments "$@"
    
    echo ""
    echo "🚀 Next.js Multi SPA App デプロイを開始します"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "環境: $ENVIRONMENT"
    echo "イメージタグ: $IMAGE_TAG"
    echo "実行ディレクトリ: $ROOT_DIR"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # オプション表示
    if [[ "$SKIP_INFRASTRUCTURE" == "true" || "$SKIP_DOCKER" == "true" || "$SKIP_STATIC" == "true" ]]; then
        echo "スキップオプション:"
        [[ "$SKIP_INFRASTRUCTURE" == "true" ]] && echo "  ⏭️  インフラストラクチャ"
        [[ "$SKIP_DOCKER" == "true" ]] && echo "  ⏭️  Dockerイメージ"
        [[ "$SKIP_STATIC" == "true" ]] && echo "  ⏭️  静的ファイル"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    
    # 前提条件チェック
    check_prerequisites
    
    # インフラストラクチャデプロイ
    if [[ "$SKIP_INFRASTRUCTURE" == "false" ]]; then
        deploy_infrastructure
        # ECRリポジトリ情報取得
        get_ecr_repository
    else
        log_warning "インフラストラクチャのデプロイをスキップしました"
        # スキップ時でもECR情報は必要
        get_ecr_repository
    fi
    
    # Dockerイメージビルド・プッシュ
    if [[ "$SKIP_DOCKER" == "false" ]]; then
        build_and_push_image
    else
        log_warning "Dockerイメージのビルド・プッシュをスキップしました"
    fi
    
    # 静的ファイルデプロイ
    if [[ "$SKIP_STATIC" == "false" ]]; then
        deploy_static_files
    else
        log_warning "静的ファイルのデプロイをスキップしました"
    fi
    
    # デプロイ情報表示
    show_deployment_info
    
    echo ""
    log_success "🎉 全てのデプロイが完了しました!"
    echo ""
}

# スクリプト実行
main "$@"
