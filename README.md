# Next.js Multi SPA App Infrastructure

Next.jsのAPI Routeで動的コンテンツを配信し、静的部分をCloudFrontでキャッシュするインフラストラクチャ構成のTerraformプロジェクトです。

## 🏗️ アーキテクチャ

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Browser   │────│ CloudFront  │────│     S3      │
└─────────────┘    └─────────────┘    └─────────────┘
                          │            (静的ファイル)
                          │
                          ▼
                   ┌─────────────┐
                   │ App Runner  │
                   └─────────────┘
                   (API Routes)
                          │
                          ▼
                   ┌─────────────┐
                   │     ECR     │
                   └─────────────┘
                   (Dockerイメージ)
```

### 設計思想

- **静的部分**: Next.js Static Exports → S3 → CloudFront（長期キャッシュ）
- **動的部分**: Next.js API Routes → App Runner → CloudFront（キャッシュ無効）

## 🚀 クイックスタート

### 前提条件

- [Node.js](https://nodejs.org/) (v18以上)
- [Docker](https://www.docker.com/)
- [Terraform](https://www.terraform.io/) (v1.0以上)
- [AWS CLI](https://aws.amazon.com/cli/) (v2.0以上)
- AWS アカウントと適切なIAM権限

### 1分デプロイ

```bash
# 1. 設定ファイルの準備
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars

# 2. 一括デプロイ実行
./scripts/deploy.sh dev latest

# 3. 完了！CloudFrontのURLが表示されます
```

## 📁 構成要素

### インフラリソース

| リソース | 用途 | 特徴 |
|----------|------|------|
| **S3** | 静的ファイルホスティング | バージョニング、暗号化、ライフサイクル管理 |
| **CloudFront** | CDN・キャッシュ | Origin Access Control、カスタムエラーページ |
| **ECR** | Dockerイメージリポジトリ | 脆弱性スキャン、ライフサイクルポリシー |
| **App Runner** | コンテナ実行環境 | オートスケーリング、ヘルスチェック |
| **IAM** | アクセス制御 | 最小権限の原則 |

### Terraformモジュール

```
terraform/
├── main.tf                    # メイン設定・モジュール呼び出し
├── variables.tf               # 共通変数定義  
├── outputs.tf                 # 出力値定義
├── .gitignore                # Git除外設定
├── modules/                  # 再利用可能なモジュール
│   ├── ecr/                 # ECRリポジトリ管理
│   ├── s3/                  # S3バケット・OAC設定
│   ├── app-runner/          # App Runnerサービス・IAM
│   └── cloudfront/          # CloudFront・キャッシュポリシー
└── environments/            # 環境別設定
    ├── dev/                # 開発環境（低コスト構成）
    └── prod/               # 本番環境（高性能構成）
```

## ⚡ 機能

### 🔄 自動デプロイ

- **インフラ**: Terraformによる宣言的構成管理
- **アプリ**: シェルスクリプトによる一括デプロイ
- **キャッシュ**: CloudFrontの自動無効化

### 📊 監視・ログ

- **App Runner**: CloudWatch Logs統合
- **CloudFront**: アクセスログ（オプション）
- **メトリクス**: CPU、メモリ、リクエスト数

### 🔐 セキュリティ

- **S3**: Origin Access Control、公開アクセスブロック
- **IAM**: 最小権限ロール
- **通信**: HTTPS強制、暗号化

### 💰 コスト最適化

- **開発環境**: 低スペック、キャッシュ短縮、ログ無効
- **CloudFront**: 地域別価格クラス選択
- **ライフサイクル**: 古いイメージ・ログの自動削除

## 🛠️ 詳細なデプロイ手順

詳細なデプロイ手順、設定のカスタマイズ、トラブルシューティングについては、[DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) をご覧ください。

### 主要コマンド

```bash
# 開発環境デプロイ
./scripts/deploy.sh dev latest

# 本番環境デプロイ  
./scripts/deploy.sh prod v1.0.0

# リソース削除
./scripts/cleanup.sh dev

# 手動デプロイ
cd terraform/environments/dev
terraform init && terraform apply
```

## 🔧 設定例

### 開発環境設定

```hcl
# terraform/environments/dev/terraform.tfvars
aws_region   = "ap-northeast-1"
project_name = "multi-spa-app"

# コスト最適化
app_runner_cpu    = "0.25 vCPU"
app_runner_memory = "0.5 GB"
cloudfront_price_class = "PriceClass_100"
enable_cloudfront_logging = false
```

### 本番環境設定

```hcl
# terraform/environments/prod/terraform.tfvars
aws_region   = "ap-northeast-1"
project_name = "multi-spa-app"
domain_name  = "example.com"

# 高性能設定
app_runner_cpu    = "1 vCPU"
app_runner_memory = "2 GB"
cloudfront_price_class = "PriceClass_All"
enable_cloudfront_logging = true
```

## 🎯 キャッシュ戦略

| パス | オリジン | TTL | 用途 |
|------|----------|-----|------|
| `/*` | S3 | 1日〜1年 | HTML、CSS、JS、画像 |
| `/api/*` | App Runner | 0秒 | 動的API、ユーザー情報 |

### パフォーマンス

- **静的コンテンツ**: Edge配信で高速化
- **動的API**: App Runnerで低レイテンシ
- **キャッシュヒット率**: 90%以上を目標

## 📈 スケーラビリティ

### App Runner自動スケーリング

```hcl
# 自動スケーリング設定
max_concurrency = 100  # 同時接続数
max_size        = 10   # 最大インスタンス数
min_size        = 1    # 最小インスタンス数
```

### 地理的分散

- **CloudFront**: 世界中のエッジロケーション
- **App Runner**: 複数AZ展開
- **S3**: 高可用性設計

## 🧪 テスト・品質

### インフラテスト

```bash
# Terraformプランテスト
terraform plan -detailed-exitcode

# セキュリティスキャン
tfsec terraform/

# 設定検証
terraform validate
```

### アプリケーションテスト

```bash
# ヘルスチェック
curl https://[CLOUDFRONT_DOMAIN]/api/health

# 静的ファイル確認
curl https://[CLOUDFRONT_DOMAIN]/

# パフォーマンステスト
ab -n 1000 -c 10 https://[CLOUDFRONT_DOMAIN]/
```

## 🚨 トラブルシューティング

### よくある問題

1. **M1/M2 Mac**: `--platform linux/amd64` オプション必須
2. **権限エラー**: IAMポリシー確認
3. **ヘルスチェック失敗**: `/api/health` エンドポイント実装

### デバッグコマンド

```bash
# ログ確認
aws logs tail /aws/apprunner/multi-spa-app-dev/application --follow

# リソース状態確認  
terraform show
aws apprunner describe-service --service-arn [ARN]
```

## 🤝 コントリビューション

1. Issueで問題報告・機能提案
2. フォークして機能開発
3. プルリクエスト作成
4. レビュー・マージ

### 開発環境

```bash
# リポジトリクローン
git clone https://github.com/your-username/multi-spa-infrastructure.git

# 開発環境セットアップ
cd multi-spa-infrastructure
./scripts/deploy.sh dev latest
```

## 📝 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照

## 🔗 関連リンク

- **フロントエンドアプリ**: [multi-spa-app](https://github.com/ryota-09/multi-spa-app)
- **参考記事**: [Next.js の API Route で動的コンテンツを配信して静的部分を CloudFront でキャッシュしてみた](https://dev.classmethod.jp/articles/nextjs-static-cache/)
- **AWS App Runner**: [公式ドキュメント](https://docs.aws.amazon.com/apprunner/)
- **Terraform AWS Provider**: [公式ドキュメント](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

⭐ このプロジェクトが役に立ったら、ぜひスターをお願いします！
