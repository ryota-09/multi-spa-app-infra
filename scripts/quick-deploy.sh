#!/bin/bash

# クイックデプロイスクリプト
# 使用方法: ./scripts/quick-deploy.sh [mode] [environment]
# モード: full, infra, app, static

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=${1:-app}
ENVIRONMENT=${2:-dev}

# 色付きログ用
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

case $MODE in
    "full")
        log_info "フルデプロイを実行します (インフラ + アプリ + 静的ファイル)"
        "$SCRIPT_DIR/deploy.sh" "$ENVIRONMENT" latest --force-yes
        ;;
    "infra")
        log_info "インフラストラクチャのみをデプロイします"
        "$SCRIPT_DIR/deploy.sh" "$ENVIRONMENT" latest --skip-docker --skip-static --force-yes
        ;;
    "app")
        log_info "アプリケーション(Docker)のみをデプロイします"
        "$SCRIPT_DIR/deploy.sh" "$ENVIRONMENT" latest --skip-infrastructure --skip-static --force-yes
        ;;
    "static")
        log_info "静的ファイルのみをデプロイします"
        "$SCRIPT_DIR/deploy.sh" "$ENVIRONMENT" latest --skip-infrastructure --skip-docker --force-yes
        ;;
    "help"|"--help"|"-h")
        echo "クイックデプロイスクリプト"
        echo ""
        echo "使用方法: $0 [mode] [environment]"
        echo ""
        echo "モード:"
        echo "  full     フルデプロイ (インフラ + アプリ + 静的ファイル) [デフォルト]"
        echo "  infra    インフラストラクチャのみ"
        echo "  app      アプリケーション(Docker)のみ"
        echo "  static   静的ファイルのみ"
        echo ""
        echo "環境:"
        echo "  dev      開発環境 [デフォルト]"
        echo "  prod     本番環境"
        echo ""
        echo "例:"
        echo "  $0 app dev          # 開発環境にアプリのみデプロイ"
        echo "  $0 static prod      # 本番環境に静的ファイルのみデプロイ"
        echo "  $0 full dev         # 開発環境にフルデプロイ"
        ;;
    *)
        log_warning "不明なモード: $MODE"
        echo "使用可能なモード: full, infra, app, static"
        echo "ヘルプを表示するには: $0 help"
        exit 1
        ;;
esac

log_success "クイックデプロイ完了!"
