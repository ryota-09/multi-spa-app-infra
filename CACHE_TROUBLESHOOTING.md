# CloudFront キャッシュ問題の解決手順

## 🚨 JavaScript 403 エラーの解決方法

### 1. 静的ファイルの再デプロイ

```bash
cd frontend
npm run deploy:static:dev
```

### 2. ブラウザキャッシュのクリア

以下の方法でブラウザキャッシュをクリアしてください：

#### Chrome/Edge

- `Ctrl + Shift + R` (Windows) または `Cmd + Shift + R` (Mac)
- または開発者ツール（F12）→ Network タブ → "Disable cache" をチェック

#### Safari

- `Cmd + Option + R` でページをリロード
- または環境設定 → プライバシー → "Web サイトデータを管理" → "すべてを削除"

#### Firefox

- `Ctrl + Shift + R` (Windows) または `Cmd + Shift + R` (Mac)
- または開発者ツール（F12）→ ネットワーク → 歯車アイコン → "キャッシュを無効化"

### 3. プライベート/シークレットモードでテスト

- Chrome: `Ctrl + Shift + N`
- Safari: `Cmd + Shift + N`
- Firefox: `Ctrl + Shift + P`

### 4. CloudFront 強制キャッシュクリア

```bash
aws cloudfront create-invalidation --distribution-id EIK13CYZSODAA --paths "/*"
```

### 5. DNS キャッシュのクリア

```bash
# Windows
ipconfig /flushdns

# macOS
sudo dscacheutil -flushcache

# Linux
sudo systemctl restart systemd-resolved
```

## 🔧 修正された問題

1. **JavaScript ファイルのハッシュ不一致**

   - 静的ビルドと S3 のファイルが同期されていなかった
   - `npm run deploy:static:dev` で解決

2. **CloudFront キャッシュ設定**

   - 古い `forwarded_values` から現代的な `cache_policy_id` に更新
   - HTML ファイルのキャッシュを短期化

3. **ビルド設定**
   - `/test-route` に `export const dynamic = "force-static"` を追加

## 📊 現在の状況

✅ **解決済み**:

- JavaScript ファイル `4bd1b696-52a6696c08e3276c.js` が正常配信（HTTP 200）
- S3 に正しいファイルがアップロード済み
- CloudFront 設定が最適化済み

⚠️ **ユーザー側で必要な対応**:

- ブラウザキャッシュのクリア
- ハードリフレッシュ（`Ctrl + Shift + R`）

## 🌐 アクセス URL

https://d3k5atvx30m82g.cloudfront.net

## 🛠️ 今後のデプロイ

フロントエンドに変更を加えた場合：

```bash
cd frontend
npm run deploy:static:dev
```

これにより自動的に：

1. 静的ビルド実行
2. S3 アップロード
3. CloudFront キャッシュ無効化

が実行されます。
