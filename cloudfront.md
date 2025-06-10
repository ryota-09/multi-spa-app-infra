403 エラーで JS が読み込めない主な原因と対策（日本語まとめ）

#	想定原因	典型的な症状	確認ポイント	解決策
1	CloudFront ビヘイビアの誤設定	_next/static/...js や /api/* が誤ったオリジンへ転送され 403 / 404	CloudFront の CacheBehavior が /api/* → App Runner、* → S3 になっているか。優先順位も確認	Terraform で ordered_cache_behavior を定義し、/api/* を S3 より前に配置
2	S3 バケットポリシー／OAC の不足	すべての S3 オブジェクトが AccessDenied	バケットポリシーに cloudfront.amazonaws.com への s3:GetObject があるか	OAC(OAI) 用ポリシーを追加し、AWS:SourceArn を対象ディストリビューションに限定
3	JS ファイルそのものが S3 にない	特定の JS だけ 403 / 404	aws s3 ls s3://bucket/_next/... で実物を確認	CI/CD で aws s3 sync out/ s3://bucket --delete などを徹底
4	ビルド ID／ハッシュ不一致	HTML は返るが参照 JS が存在せず 403	App Runner の .next/BUILD_ID と S3 用ビルドの BUILD_ID を比較	単一ビルドを両環境へ配布 するか、generateBuildId で固定 ID を利用
5	「/login」など末尾スラッシュ問題	ルート直打ちで 403（index.html が解決されない）	/login/ と /login の両方をテスト	① S3 静的ホスティングを使う② CloudFront Function で /dir → /dir/index.html に書き換え
6	キャッシュとデプロイの非同期	デプロイ直後にだけ 403 / 404	CloudFront ヒット時に古い HTML が残っていないか	デプロイ後に /* もしくは HTML/JSON のみを create-invalidation で無効化


⸻

Terraform で最低限押さえるポイント

# --- CloudFront ---
ordered_cache_behavior {
  path_pattern     = "/api/*"
  target_origin_id = "AppRunnerOrigin"
  cache_policy_id  = aws_cloudfront_cache_policy.no_cache.id
}
# default_cache_behavior → S3Origin（長期キャッシュ）

# --- S3 バケットポリシー（OAC 版） ---
data "aws_iam_policy_document" "oac" {
  statement {
    principals  { type = "Service" identifiers = ["cloudfront.amazonaws.com"] }
    actions     = ["s3:GetObject"]
    resources   = ["${aws_s3_bucket.static.arn}/*"]
    condition   { test = "StringEquals" variable = "AWS:SourceArn" values = [aws_cloudfront_distribution.site.arn] }
  }
}
resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.oac.json
}


⸻

デバッグ手順（実務向けチェックリスト）
	1.	CloudFront ログ確認
	•	403 行の x-edge-result-type が Error なら S3/OAC、OriginShield なら OAC かビルド不一致を疑う。
	2.	S3 アクセスログ／CLI で存在確認
	•	aws s3api head-object で 404 (NoSuchKey) ならファイル未配置。403 ならポリシー不備。
	3.	BUILD_ID 一致確認

cat .next/BUILD_ID          # S3 用ビルド
# App Runner に ssh exec できるなら同様に確認


	4.	URL 末尾チェック
	•	/login と /login/ で挙動差がないか。差があればリライトルールを導入。
	5.	キャッシュ無効化
	•	新ビルド後に

aws cloudfront create-invalidation --distribution-id XXXXXX --paths "/*"

あるいは HTML/JSON だけ短 TTL を設定。

⸻

まとめ
	•	403 の 8 割は「誤ルーティング」か「権限不備」
→ CloudFront ビヘイビア順序と S3 ポリシーをまず疑う。
	•	残りは「ファイル不在」か「ビルド差分」
→ 単一ビルド運用 & aws s3 sync が鉄則。
	•	きれいな URL を保ちたいなら CloudFront Function で index.html 補完。
	•	キャッシュは HTML と API を短 TTL／無効化、ハッシュ付き静的アセットは長期 TTL。

これらを順番に確認すれば、Next.js ハイブリッド構成での JS 403 問題はほぼ解決できます。