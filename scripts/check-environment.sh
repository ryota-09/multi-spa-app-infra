#!/bin/bash

# デプロイ環境チェックスクリプト
# 使用方法: ./scripts/check-environment.sh [environment]

set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 色付きログ用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_check() {
    echo -e "${PURPLE}[CHECK]${NC} $1"
}

# 各種チェック関数
check_commands() {
    log_check "必要なコマンドの確認"
    
    local commands=("aws" "docker" "terraform" "npm" "jq" "git")
    local missing=()
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            local version
            case $cmd in
                "aws")
                    version=$(aws --version 2>&1 | cut -d' ' -f1)
                    ;;
                "docker")
                    version=$(docker --version | cut -d' ' -f3 | tr -d ',')
                    ;;
                "terraform")
                    version=$(terraform version | head -n1 | cut -d'v' -f2)
                    ;;
                "npm")
                    version=$(npm --version)
                    ;;
                "jq")
                    version=$(jq --version | tr -d '"')
                    ;;
                "git")
                    version=$(git --version | cut -d' ' -f3)
                    ;;
            esac
            log_success "$cmd ($version)"
        else
            missing+=("$cmd")
            log_error "$cmd が見つかりません"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_warning "以下のコマンドをインストールしてください:"
        for cmd in "${missing[@]}"; do
            case $cmd in
                "aws")
                    echo "  - AWS CLI: brew install awscli"
                    ;;
                "docker")
                    echo "  - Docker: https://www.docker.com/products/docker-desktop"
                    ;;
                "terraform")
                    echo "  - Terraform: brew install terraform"
                    ;;
                "npm")
                    echo "  - Node.js/npm: brew install node"
                    ;;
                "jq")
                    echo "  - jq: brew install jq"
                    ;;
                "git")
                    echo "  - Git: brew install git"
                    ;;
            esac
        done
        return 1
    fi
    return 0
}

check_aws_config() {
    log_check "AWS設定の確認"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証が設定されていません"
        echo "  設定方法:"
        echo "    aws configure"
        echo "  または環境変数:"
        echo "    export AWS_ACCESS_KEY_ID=your-key"
        echo "    export AWS_SECRET_ACCESS_KEY=your-secret"
        return 1
    fi
    
    local account_id region
    account_id=$(aws sts get-caller-identity --query Account --output text)
    region=$(aws configure get region || echo "未設定")
    
    log_success "AWS Account ID: $account_id"
    log_success "AWS Region: $region"
    
    if [[ "$region" != "ap-northeast-1" ]]; then
        log_warning "リージョンがap-northeast-1ではありません。Terraformファイルを確認してください。"
    fi
    
    return 0
}

check_docker() {
    log_check "Docker環境の確認"
    
    if ! docker info &> /dev/null; then
        log_error "Dockerデーモンが起動していません"
        echo "  Docker Desktopを起動してください"
        return 1
    fi
    
    local docker_info
    docker_info=$(docker info --format "{{.ServerVersion}}")
    log_success "Docker デーモン ($docker_info) が起動中"
    
    # ディスク使用量確認
    local disk_usage
    disk_usage=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" | tail -n +2)
    if [[ -n "$disk_usage" ]]; then
        echo "  Dockerディスク使用量:"
        echo "$disk_usage" | while read -r line; do
            echo "    $line"
        done
    fi
    
    return 0
}

check_terraform_config() {
    log_check "Terraform設定の確認"
    
    local env_dir="$ROOT_DIR/terraform/environments/$ENVIRONMENT"
    
    if [[ ! -d "$env_dir" ]]; then
        log_error "環境ディレクトリが見つかりません: $env_dir"
        return 1
    fi
    
    log_success "環境ディレクトリ: $env_dir"
    
    # terraform.tfvars確認
    if [[ ! -f "$env_dir/terraform.tfvars" ]]; then
        log_warning "terraform.tfvarsファイルが見つかりません"
        if [[ -f "$env_dir/terraform.tfvars.example" ]]; then
            echo "  terraform.tfvars.exampleをコピーして設定してください:"
            echo "    cp $env_dir/terraform.tfvars.example $env_dir/terraform.tfvars"
        fi
        return 1
    fi
    
    log_success "terraform.tfvars ファイル存在確認"
    
    # Terraform初期化状態確認
    cd "$env_dir"
    if [[ ! -d ".terraform" ]]; then
        log_warning "Terraformが初期化されていません"
        echo "  初期化方法: terraform init"
        cd "$ROOT_DIR"
        return 1
    fi
    
    log_success "Terraform初期化済み"
    
    # リモートステート確認
    if terraform show &> /dev/null; then
        log_success "Terraformステートファイル確認済み"
        
        # リソース数確認
        local resource_count
        resource_count=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$resource_count" -gt 0 ]]; then
            log_success "デプロイ済みリソース: $resource_count 個"
        else
            log_warning "デプロイされたリソースが見つかりません"
        fi
    else
        log_warning "Terraformステートファイルに問題があります"
    fi
    
    cd "$ROOT_DIR"
    return 0
}

check_frontend_config() {
    log_check "フロントエンド設定の確認"
    
    local frontend_dir="$ROOT_DIR/frontend"
    
    if [[ ! -d "$frontend_dir" ]]; then
        log_error "frontendディレクトリが見つかりません"
        return 1
    fi
    
    cd "$frontend_dir"
    
    # package.json確認
    if [[ ! -f "package.json" ]]; then
        log_error "package.jsonが見つかりません"
        cd "$ROOT_DIR"
        return 1
    fi
    
    log_success "package.json 存在確認"
    
    # 必要なスクリプト確認
    local scripts=("build:static" "dev" "build")
    for script in "${scripts[@]}"; do
        if jq -e ".scripts.\"$script\"" package.json > /dev/null 2>&1; then
            log_success "npm script '$script' 確認済み"
        else
            log_error "npm script '$script' が見つかりません"
        fi
    done
    
    # node_modules確認
    if [[ ! -d "node_modules" ]]; then
        log_warning "node_modulesが見つかりません"
        echo "  依存関係をインストール: npm install"
    else
        log_success "node_modules 存在確認"
        
        # package-lock.json確認
        if [[ -f "package-lock.json" ]]; then
            if [[ "package.json" -nt "node_modules" ]]; then
                log_warning "package.jsonが更新されています。npm installを実行してください"
            fi
        fi
    fi
    
    # Dockerfile確認
    if [[ ! -f "Dockerfile" ]]; then
        log_error "Dockerfileが見つかりません"
        cd "$ROOT_DIR"
        return 1
    fi
    
    log_success "Dockerfile 存在確認"
    
    cd "$ROOT_DIR"
    return 0
}

check_deployment_status() {
    log_check "デプロイ状況の確認"
    
    local env_dir="$ROOT_DIR/terraform/environments/$ENVIRONMENT"
    cd "$env_dir"
    
    if ! terraform show &> /dev/null; then
        log_warning "インフラストラクチャがデプロイされていません"
        cd "$ROOT_DIR"
        return 1
    fi
    
    # 各リソースの状態確認
    local outputs
    outputs=$(terraform output -json 2>/dev/null || echo "{}")
    
    if [[ "$outputs" != "{}" ]]; then
        echo ""
        echo "🔍 現在のデプロイ状況:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # ECR確認
        local ecr_uri
        ecr_uri=$(echo "$outputs" | jq -r '.ecr_repository_uri.value // empty')
        if [[ -n "$ecr_uri" ]]; then
            log_success "ECR: $ecr_uri"
            
            # イメージ確認
            local repo_name
            repo_name=$(echo "$ecr_uri" | cut -d'/' -f2)
            local image_count
            image_count=$(aws ecr describe-images --repository-name "$repo_name" --query 'length(imageDetails)' --output text 2>/dev/null || echo "0")
            echo "  イメージ数: $image_count"
        fi
        
        # App Runner確認
        local app_runner_url
        app_runner_url=$(echo "$outputs" | jq -r '.app_runner_service_url.value // empty')
        if [[ -n "$app_runner_url" ]]; then
            log_success "App Runner: https://$app_runner_url"
            
            # ヘルスチェック
            if curl -s -o /dev/null -w "%{http_code}" "https://$app_runner_url" | grep -q "200"; then
                log_success "App Runner サービス: 正常稼働中"
            else
                log_warning "App Runner サービス: 応答なし"
            fi
        fi
        
        # S3 + CloudFront確認
        local website_url
        website_url=$(echo "$outputs" | jq -r '.website_url.value // empty')
        if [[ -n "$website_url" ]]; then
            log_success "Website: $website_url"
            
            # ヘルスチェック
            if curl -s -o /dev/null -w "%{http_code}" "$website_url" | grep -q "200"; then
                log_success "静的サイト: 正常稼働中"
            else
                log_warning "静的サイト: 応答なし"
            fi
        fi
    fi
    
    cd "$ROOT_DIR"
    return 0
}

show_recommendations() {
    echo ""
    echo "💡 推奨アクション:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 初回デプロイかどうか確認
    local env_dir="$ROOT_DIR/terraform/environments/$ENVIRONMENT"
    if [[ ! -f "$env_dir/terraform.tfstate" ]] || [[ ! -s "$env_dir/terraform.tfstate" ]]; then
        echo "🚀 初回デプロイの場合:"
        echo "  ./scripts/deploy.sh $ENVIRONMENT latest"
        echo ""
    fi
    
    echo "📦 部分的なデプロイ:"
    echo "  ./scripts/quick-deploy.sh app $ENVIRONMENT      # アプリのみ"
    echo "  ./scripts/quick-deploy.sh static $ENVIRONMENT   # 静的ファイルのみ"
    echo "  ./scripts/quick-deploy.sh infra $ENVIRONMENT    # インフラのみ"
    echo ""
    
    echo "🔧 トラブルシューティング:"
    echo "  ./scripts/cleanup.sh                            # リソースクリーンアップ"
    echo "  docker system prune -f                          # Dockerキャッシュクリア"
    echo "  cd terraform/environments/$ENVIRONMENT && terraform plan  # 設定確認"
    echo ""
}

# メイン処理
main() {
    echo ""
    echo "🔍 Multi SPA App デプロイ環境チェック"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "環境: $ENVIRONMENT"
    echo "チェック日時: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local all_checks_passed=true
    
    # 各種チェック実行
    if ! check_commands; then
        all_checks_passed=false
    fi
    echo ""
    
    if ! check_aws_config; then
        all_checks_passed=false
    fi
    echo ""
    
    if ! check_docker; then
        all_checks_passed=false
    fi
    echo ""
    
    if ! check_terraform_config; then
        all_checks_passed=false
    fi
    echo ""
    
    if ! check_frontend_config; then
        all_checks_passed=false
    fi
    echo ""
    
    check_deployment_status
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$all_checks_passed" == "true" ]]; then
        echo "✅ 全てのチェックが完了しました。デプロイ準備完了！"
    else
        echo "❌ いくつかの問題が見つかりました。上記の指示に従って修正してください。"
    fi
    
    show_recommendations
}

# ヘルプ表示
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "デプロイ環境チェックスクリプト"
    echo ""
    echo "使用方法: $0 [environment]"
    echo ""
    echo "引数:"
    echo "  environment   チェック対象の環境 (デフォルト: dev)"
    echo ""
    echo "このスクリプトは以下をチェックします:"
    echo "  - 必要なコマンドのインストール状況"
    echo "  - AWS設定"
    echo "  - Docker環境"
    echo "  - Terraform設定"
    echo "  - フロントエンド設定"
    echo "  - 現在のデプロイ状況"
    exit 0
fi

# スクリプト実行
main
