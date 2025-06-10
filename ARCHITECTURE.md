# アーキテクチャドキュメント

## システム概要

本プロジェクトは、Next.js の API Route で動的コンテンツを配信し、静的部分を CloudFront でキャッシュするハイブリッド構成を実装しています。

## 全体構成図

```
┌─────────────────┐
│  CloudFront CDN │
└─────────────────┘
         │
         ├─── /login* ─────► App Runner (Next.js動的実行)
         ├─── /api/* ──────► App Runner (API Routes)
         └─── /* ──────────► S3 (静的ファイル)
```

## コンポーネント構成

### 1. CloudFront Distribution
- **役割**: エッジキャッシュとルーティング
- **パスベースルーティング**:
  - `/login*` → App Runner (キャッシュ無効)
  - `/api/*` → App Runner (キャッシュ無効)
  - `/*` → S3 (静的キャッシュ)

### 2. App Runner
- **役割**: 動的コンテンツ配信
- **実行内容**:
  - ログインページ (`/login`)
  - API Routes (`/api/*`)
  - Next.js standaloneモードで実行

### 3. S3 + Static Website Hosting
- **役割**: 静的コンテンツ配信
- **内容**:
  - トップページ (`/`)
  - 商品ページ (`/products/*`)
  - 静的アセット (CSS, JS, 画像)

### 4. ECR
- **役割**: Dockerイメージ管理
- **内容**: App Runner用のNext.jsアプリケーションイメージ

## 技術仕様

### Next.js 設定

#### 環境変数による出力モード切り替え
```typescript
const nextConfig: NextConfig = {
  output: process.env.NODE_ENV === 'production' 
    ? (process.env.STANDALONE === "true" ? "standalone" : "export")
    : undefined,
  trailingSlash: true,
  images: {
    unoptimized: process.env.NODE_ENV === 'production' && process.env.STANDALONE !== "true",
  },
};
```

#### ビルドモード
1. **静的エクスポート**: `npm run build:static`
   - APIディレクトリを一時的に除外
   - 静的ファイルを `out/` ディレクトリに生成
   - S3にデプロイ

2. **スタンドアロン**: `npm run build:standalone`
   - `STANDALONE=true` 環境変数設定
   - 動的実行用ビルド
   - App Runnerにデプロイ

### CloudFront Cache Behaviors

#### 静的コンテンツ (デフォルト)
```hcl
default_cache_behavior {
  target_origin_id = "S3-bucket"
  viewer_protocol_policy = "redirect-to-https"
  cached_methods = ["GET", "HEAD"]
  default_ttl = 86400  # 24時間
  max_ttl = 31536000   # 1年
}
```

#### 動的コンテンツ (/api/*)
```hcl
ordered_cache_behavior {
  path_pattern = "/api/*"
  target_origin_id = "AppRunner-service"
  min_ttl = 0
  default_ttl = 0
  max_ttl = 0
  cache_policy = "CACHING_DISABLED"
}
```

#### ログインページ (/login*)
```hcl
ordered_cache_behavior {
  path_pattern = "/login*"
  target_origin_id = "AppRunner-service"
  min_ttl = 0
  default_ttl = 0
  max_ttl = 0
  cache_policy = "CACHING_DISABLED"
}
```

## デプロイメント

### インフラストラクチャ
```bash
# Terraformでインフラをデプロイ
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

### アプリケーション

#### 1. 静的サイト (S3)
```bash
# 静的ファイルをS3にデプロイ
./scripts/deploy-frontend.sh dev
```

#### 2. 動的アプリケーション (App Runner)
```bash
# DockerイメージをECRにプッシュ
cd frontend
npm run ecr:push:dev

# App Runnerが自動デプロイを実行
```

## セキュリティ考慮事項

### Origin Access Control (OAC)
- S3バケットへの直接アクセスを制限
- CloudFront経由のみアクセス許可

### HTTPS強制
- 全てのトラフィックをHTTPSにリダイレクト
- TLS 1.2以降のみサポート

### IAM設定
- 最小権限の原則に従ったロール設定
- App Runner専用のIAMロール

## 監視・ログ

### CloudWatch Logs
- App Runnerのアプリケーションログ
- CloudFrontアクセスログ (オプション)

### メトリクス
- CloudFrontのリクエスト/キャッシュヒット率
- App Runnerのレスポンス時間/エラー率

## パフォーマンス最適化

### キャッシュ戦略
- 静的コンテンツ: 長期キャッシュ (1年)
- 動的コンテンツ: キャッシュ無効
- 適切なCache-Controlヘッダー設定

### 画像最適化
- 静的ビルド時に最適化済み画像を生成
- WebP対応 (ブラウザサポートに応じて)

## トラブルシューティング

### よくある問題

1. **静的ビルドでAPIエラー**
   - APIディレクトリが静的ビルドに含まれている
   - `build-static.js` スクリプトを使用

2. **App Runnerで接続エラー**
   - `HOSTNAME=0.0.0.0` 環境変数が設定されているか確認
   - Dockerfile内の設定を確認

3. **CloudFrontキャッシュ問題**
   - 適切なパスパターンが設定されているか確認
   - キャッシュ無効化を実行

## 参考資料
- [Next.js の API Route で動的コンテンツを配信して静的部分を CloudFront でキャッシュしてみた](https://dev.classmethod.jp/articles/nextjs-static-cache/)
- [Next.js Static Exports Documentation](https://nextjs.org/docs/app/building-your-application/deploying/static-exports)
- [AWS App Runner Documentation](https://docs.aws.amazon.com/apprunner/)
