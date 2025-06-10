NextAuth.js 利用時に 403 が起きやすいポイントと対処法（CloudFront ＋ App Runner 構成）

想定原因	症状（例）	重点確認	代表的な対策
① CloudFront が Cookie / クエリ文字列を Origin に転送していない	/api/auth/callback や /api/auth/session が 403。ブラウザ開発ツールでリクエストを見ると Cookie が送られていない	CloudFront の /api/* ビヘイビアに Origin Request Policy が付いているか。デフォルトのままだと Cookie・Query がカットされる	/api/* ビヘイビアに AllViewer（ID: 33f36d7e-f396-46d9-90e0-52428a34d9dc）など 全ヘッダー・全 Cookie・全クエリ を転送するポリシーを設定する  ￼
② Allowed Methods が GET/HEAD だけ	OAuth コールバック（POST）や 資格情報ログインの POST が即 403/405	CloudFront の Allowed Methods が GET,HEAD,OPTIONS,POST などになっているか	/api/* の Allowed Methods を POST まで許可し、CacheMethods は GET/HEAD のみキャッシュにする  ￼
③ CSRF／state Cookie が欠落	NextAuth が “CSRF token mismatch” や OAuthCallbackError を返す（ステータス 403）	App Runner のログ、または NextAuth エラーメッセージ	①の Cookie 転送を必ず有効化。ブラウザ拡張やサードパーティ Cookie 制限でブロックされていないかも確認  ￼
④ Secure/SameSite 設定とドメインの不一致	Cookie が発行されてもブラウザに保存されない or 送信されない	NEXTAUTH_URL が https で CloudFront の公開 URL と一致しているか。Cookie のドメインを手動指定していないか	NEXTAUTH_URL=https://<公開ドメイン> を設定。基本はデフォルトの Secure=true, SameSite=Lax で OK。複数ドメインを跨ぐ場合のみ SameSite=None + Secure を検討  ￼
⑤ CloudFront が /api/auth/* をキャッシュ	一度ログインした別ユーザーのセッション結果が返る／常に同じレスポンス	/api/auth/… が CloudFront で HIT になっていないか	/api/auth/* に CachingDisabled ポリシーを適用し TTL=0 にする  ￼
⑥ CORS 設定不足（クロスドメイン時のみ）	ブラウザ Console に “CORS policy” エラー。Network タブでは 403 でレスポンスヘッダーに Access-Control-* が無い	API を別ドメイン／サブドメインで呼んでいないか	CloudFront Response-Headers ポリシーまたは Next.js headers() で Access-Control-Allow-Origin 等を付与し、Origin ヘッダーを転送する  ￼ ￼

実装チェックリスト
	1.	CloudFront ビヘイビア

ordered_cache_behavior {
  path_pattern     = "/api/*"
  target_origin_id = "AppRunner"
  allowed_methods  = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
  cache_policy_id          = "413fd16d-10f9-4f9f-b0b4-56bc1b56aab4"   # CachingDisabled
  origin_request_policy_id = "33f36d7e-f396-46d9-90e0-52428a34d9dc"   # AllViewer
}


	2.	S3 側は OAC で静的配信のみ許可（API には不要）。
	3.	環境変数

NEXTAUTH_URL="https://<CloudFront または独自ドメイン>"


	4.	NextAuth のオプション（基本はデフォルト）

export default NextAuth({
  // providers, etc.
  // useSecureCookies は production で true
  cookies: {
    // クロスドメインが必要な場合のみ SameSite=None を設定
  },
})


	5.	デプロイ後テスト
	•	/api/auth/csrf が 200 で __Host-next-auth.csrf-token Cookie が返る
	•	/api/auth/session が 200 / 204（セッションなし）で 403 でない
	•	/api/auth/callback/<provider> が 302 → / などにリダイレクト
	•	CloudFront アクセスログで /api/auth/* が毎回 Miss（CacheStatus=Miss）になっている

まとめ

NextAuth 自体は 403 の直接原因というより、Cookie とクエリパラメータが CloudFront で落ちるとセキュリティチェックに失敗して 403 になる仕組みです。
	•	AllViewer ポリシーで Cookie・ヘッダー・クエリを転送し、
	•	POST / OPTIONS を許可し、
	•	キャッシュを無効化すれば解決するケースがほとんどです。

これらを反映させた後に再デプロイし、ブラウザと CloudFront のキャッシュをクリアしてテストしてください。