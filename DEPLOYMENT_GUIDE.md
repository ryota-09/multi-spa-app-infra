# Next.js Multi SPA App デプロイガイド

このガイドでは、Next.jsのAPI Routeで動的コンテンツを配信し、静的部分をCloudFrontでキャッシュするアプリケーションのデプロイ方法を説明します。

## 📋 前提条件

### 必要なツール
- [Node.js](https://nodejs.org/) (v18以上)
- [Docker](https://www.docker.com/)
- [Terraform](https://www.terraform.io/) (v1.0以上)
- [AWS CLI](https://aws.amazon.com/cli/) (v2.0以上)
- [jq](https://stedolan.github.io/jq/) (JSONパーサー)

### AWS設定
- AWS アカウント
- AWS CLI の認証設定済み
- 必要なIAM権限（EC2、S3、CloudFront、App Runner、ECR等）

## 🚀 クイックスタート

### 1. 設定ファイルの準備

```bash
# 設定ファイルをコピー
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars

# 設定ファイルを編集
vi terraform/environments/dev/terraform.tfvars
```

### 2. 一括デプロイ

```bash
# デプロイスクリプトに実行権限を付与
chmod +x scripts/deploy.sh

# デプロイ実行
./scripts/deploy.sh dev latest
```

### 3. アクセス

デプロイ完了後、表示されるCloudFrontのURLにアクセスしてアプリケーションを確認できます。

## 📁 プロジェクト構造

```
.
├── README.md                    # プロジェクト概要
├── DEPLOYMENT_GUIDE.md         # このファイル
├── scripts/
│   ├── deploy.sh               # デプロイスクリプト
│   └── cleanup.sh              # クリーンアップスクリプト
└── terraform/
    ├── main.tf                 # メインのTerraform設定
    ├── variables.tf            # 変数定義
    ├── outputs.tf              # 出力値定義
    ├── .gitignore             # Git除外設定
    ├── modules/               # Terraformモジュール
    │   ├── ecr/              # ECRリポジトリ
    │   ├── s3/               # S3バケット
    │   ├── app-runner/       # App Runnerサービス
    │   └── cloudfront/       # CloudFrontディストリビューション
    └── environments/
        └── dev/              # 開発環境設定
            ├── main.tf
            ├── variables.tf
            ├── outputs.tf
            └── terraform.tfvars.example
```

## ⚙️ 詳細なデプロイ手順

### Step 1: インフラストラクチャのデプロイ

```bash
cd terraform/environments/dev

# Terraform初期化
terraform init

# プランの確認
terraform plan

# インフラデプロイ
terraform apply
```

### Step 2: Dockerイメージのビルド・プッシュ

```bash
# ECRログイン
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin [ECR_URI]

# イメージビルド（M1/M2 Macの場合はplatformオプション必須）
docker build --platform linux/amd64 -t multi-spa-app:latest .

# タグ付け
docker tag multi-spa-app:latest [ECR_URI]:latest

# プッシュ
docker push [ECR_URI]:latest
```

### Step 3: 静的ファイルのデプロイ

```bash
# Next.js静的ビルド
npm install
npm run build:static

# S3にアップロード
aws s3 sync ./out s3://[BUCKET_NAME] --delete

# CloudFrontキャッシュクリア
aws cloudfront create-invalidation --distribution-id [DISTRIBUTION_ID] --paths "/*"
```

## 🔧 設定のカスタマイズ

### terraform.tfvars設定例

```hcl
# 基本設定
aws_region   = "ap-northeast-1"
project_name = "my-spa-app"

# ドメイン設定（オプショナル）
domain_name = "example.com"

# App Runner設定
app_runner_cpu    = "0.5 vCPU"
app_runner_memory = "1 GB"

# CloudFront設定
cloudfront_price_class    = "PriceClass_All"
enable_cloudfront_logging = true

# キャッシュ設定
cloudfront_cache_ttl = {
  default_ttl = 86400    # 1日
  min_ttl     = 0
  max_ttl     = 31536000 # 1年
}
```

### 環境別設定

#### 開発環境 (dev)
- App Runner: 0.25 vCPU / 0.5 GB
- CloudFront: PriceClass_100（コスト削減）
- ログ: 無効
- キャッシュ: 短期間

#### 本番環境 (prod)
- App Runner: 1 vCPU / 2 GB
- CloudFront: PriceClass_All
- ログ: 有効
- キャッシュ: 長期間

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

### キャッシュ戦略

| パス | オリジン | キャッシュ | 用途 |
|------|----------|------------|------|
| `/*` | S3 | 有効 (長期) | 静的コンテンツ |
| `/api/*` | App Runner | 無効 | 動的API |

## 🔍 トラブルシューティング

### よくある問題

#### 1. App Runnerでのビルドエラー

**問題**: M1/M2 Macでビルドしたイメージが動作しない

**解決**: platformオプションを指定してビルド
```bash
docker build --platform linux/amd64 -t app:latest .
```

#### 2. S3アクセス権限エラー

**問題**: CloudFrontからS3にアクセスできない

**解決**: バケットポリシーの確認
```bash
# Terraformで再適用
terraform apply
```

#### 3. App Runnerのヘルスチェック失敗

**問題**: `/api/health` エンドポイントが応答しない

**解決**: ヘルスチェック用エンドポイントを追加

```typescript
// src/app/api/health/route.ts
export async function GET() {
  return Response.json({ status: 'ok', timestamp: new Date().toISOString() });
}
```

### デバッグ方法

#### ログの確認

```bash
# App Runnerログ
aws logs tail /aws/apprunner/multi-spa-app-dev/application --follow

# CloudFrontアクセスログ（有効化時）
aws s3 ls s3://[LOG_BUCKET]/cloudfront-logs/
```

#### リソースの状態確認

```bash
# Terraformの状態確認
terraform show

# AWSリソースの確認
aws apprunner describe-service --service-arn [SERVICE_ARN]
aws cloudfront get-distribution --id [DISTRIBUTION_ID]
```

## 🧹 クリーンアップ

### 自動クリーンアップ

```bash
# 全リソースの削除
./scripts/cleanup.sh dev
```

### 手動クリーンアップ

```bash
# S3バケットの中身を削除
aws s3 rm s3://[BUCKET_NAME] --recursive

# Terraformでリソース削除
cd terraform/environments/dev
terraform destroy
```

## 📊 監視・運用

### 主要メトリクス

- **App Runner**: CPU使用率、メモリ使用率、リクエスト数
- **CloudFront**: キャッシュヒット率、オリジンレスポンス時間
- **S3**: リクエスト数、転送量

### アラート設定

CloudWatchアラームを設定して異常を監視：

```bash
# App Runnerの高CPU使用率アラーム
aws cloudwatch put-metric-alarm \
  --alarm-name "AppRunner-HighCPU" \
  --alarm-description "App Runner CPU usage > 80%" \
  --metric-name "CPUUtilization" \
  --namespace "AWS/AppRunner" \
  --statistic "Average" \
  --period 300 \
  --threshold 80 \
  --comparison-operator "GreaterThanThreshold"
```

## 🔐 セキュリティ

### 推奨設定

1. **IAM権限の最小化**: 必要最小限の権限のみ付与
2. **VPC設定**: App RunnerのVPC接続（必要に応じて）
3. **WAF設定**: CloudFrontでのWebアプリケーションファイアウォール
4. **SSL/TLS**: 常にHTTPS通信の強制

### セキュリティチェックリスト

- [ ] S3バケットの公開アクセスブロック有効
- [ ] CloudFrontでのHTTPS強制
- [ ] App RunnerのIAMロール最小権限
- [ ] ECRイメージの脆弱性スキャン有効
- [ ] CloudWatchログの保持期間設定

## 📝 ライセンス

MIT License

## 🤝 コントリビューション

1. フォークする
2. 機能ブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## 📞 サポート

問題や質問がある場合は、GitHubのIssuesで報告してください。
