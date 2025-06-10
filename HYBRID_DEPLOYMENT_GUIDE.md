# Next.js ハイブリッドデプロイメントガイド

## 概要

このガイドでは、Next.js アプリケーションを静的部分と動的部分に分離し、CloudFront でキャッシュ制御を行うハイブリッドデプロイメントについて説明します。

## アーキテクチャ

```
┌─────────────┐     ┌──────────────────────────────────────┐
│   Client    │────▶│          CloudFront CDN              │
└─────────────┘     └────────────┬─────────────┬──────────┘
                                 │             │
                    ┌────────────▼───┐    ┌────▼─────────┐
                    │   S3 Bucket    │    │  App Runner  │
                    │ (Static Files) │    │ (API Routes) │
                    └────────────────┘    └──────────────┘
```

### コンポーネント

1. **CloudFront**: 全てのリクエストのエントリーポイント
2. **S3**: 静的にビルドされたHTML、CSS、JS、画像ファイルを配信
3. **App Runner**: API Routes (`/api/*`) の動的コンテンツを処理

## API Routes の実装

### 1. 基本的な API Route

```typescript
// src/app/api/route.ts
import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'  // 動的レンダリングを強制

export async function GET() {
  return NextResponse.json({
    message: 'Dynamic API endpoint',
    timestamp: new Date().toISOString(),
  })
}
```

### 2. ユーザー固有のデータを返す API

```typescript
// src/app/api/user/route.ts
import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'

export const dynamic = 'force-dynamic'

export async function GET() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get('sessionId')
  
  const userData = {
    id: sessionId?.value || 'anonymous',
    name: sessionId ? `User ${sessionId.value}` : 'Guest',
    cartItems: Math.floor(Math.random() * 10),
  }
  
  return NextResponse.json(userData)
}
```

### 3. 動的パラメータを使用した API

```typescript
// src/app/api/products/[id]/route.ts
export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  
  const product = {
    id,
    inventory: Math.floor(Math.random() * 100),
    available: Math.random() > 0.2,
  }
  
  return NextResponse.json(product)
}
```

## クライアントサイドでの動的データ取得

```typescript
// src/components/DynamicUserInfo.tsx
'use client'

import { useEffect, useState } from 'react'

export function DynamicUserInfo() {
  const [userData, setUserData] = useState(null)

  useEffect(() => {
    fetch('/api/user')
      .then(res => res.json())
      .then(data => setUserData(data))
  }, [])

  if (!userData) return <div>Loading...</div>

  return (
    <div>
      <p>Welcome, {userData.name}!</p>
      <p>Cart: {userData.cartItems} items</p>
    </div>
  )
}
```

## CloudFront キャッシュ設定

### キャッシュビヘイビア

1. **静的コンテンツ** (デフォルト)
   - オリジン: S3
   - キャッシュポリシー: CACHING_OPTIMIZED
   - 長期間キャッシュ

2. **API Routes** (`/api/*`)
   - オリジン: App Runner
   - キャッシュポリシー: CACHING_DISABLED
   - キャッシュなし

3. **静的アセット** (`/_next/static/*`)
   - オリジン: S3
   - キャッシュポリシー: CACHING_OPTIMIZED
   - イミュータブルキャッシュ（ファイル名にハッシュ含む）

## デプロイメント手順

### 1. ハイブリッドビルドの実行

```bash
cd frontend
npm run build:hybrid
```

このコマンドは以下を実行します：
- App Runner 用のスタンドアロンビルド
- S3 用の静的エクスポート
- 両環境で同じハッシュの静的アセットを使用

### 2. インフラのデプロイ

```bash
cd ../scripts
./deploy-hybrid.sh
```

### 3. フロントエンドのデプロイ

```bash
./deploy-frontend.sh
```

## ベストプラクティス

### 1. API Route の設計

- 認証が必要なデータは API Route で提供
- リアルタイムデータ（在庫、価格）は API Route で提供
- 静的なコンテンツ（商品説明、画像）は静的生成

### 2. キャッシュ戦略

- API レスポンスには適切な Cache-Control ヘッダーを設定
- ユーザー固有のデータはキャッシュしない
- 共通データは短時間キャッシュを検討

### 3. パフォーマンス最適化

- 重要な API コールは並列で実行
- Loading UI を適切に実装
- エラーハンドリングを忘れずに

## トラブルシューティング

### API が 404 を返す

1. App Runner が正しくデプロイされているか確認
2. CloudFront のビヘイビアが正しく設定されているか確認
3. Next.js の設定で `trailingSlash` が適切か確認

### 静的コンテンツが更新されない

1. CloudFront のキャッシュを無効化
2. S3 バケットのファイルが更新されているか確認
3. ブラウザのキャッシュをクリア

### CORS エラーが発生する

1. API Route で適切な CORS ヘッダーを設定
2. CloudFront で OPTIONS メソッドを許可
3. App Runner の環境変数を確認