原因分析と対応策

CloudFrontのビヘイビア設定の問題

原因 (原理):
CloudFrontディストリビューションのキャッシュビヘイビア設定に不備がある可能性があります。具体的には、HTTPメソッド制限とパスルーティングです。静的コンテンツ配信向けに既定でGET/HEADしか許可していない場合、ログインフォーム送信（POSTリクエスト）がCloudFront側でブロックされ、HTTP 403になります ￼。また、/api/*パスが適切にApp Runnerオリジンへルーティングされていないと、認証API呼び出しが誤ってS3に向かいアクセス拒否される可能性があります。

該当箇所:
TerraformのCloudFrontモジュール（terraform/modules/cloudfront）で定義しているディストリビューション設定が該当します。例えばaws_cloudfront_distributionのordered_cache_behaviorでpath_patternやallowed_methods、cache_policy/origin_request_policyを設定している部分です。ここで/api/*がApp Runnerオリジンに割り当てられ、POSTやOPTIONSを含む必要なHTTPメソッドが許可されているか確認します。

修正方針:
	•	POSTメソッドの許可: CloudFrontビヘイビアで/api/*に対して全てのHTTPメソッドを許可します。Terraformでは、例えば以下のように設定します（allowed_methodsとcached_methodsを適切に指定） ￼:

ordered_cache_behavior {
  path_pattern = "/api/*"
  target_origin_id = "apprunner-origin"
  allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
  cached_methods   = ["GET", "HEAD"]  # キャッシュ対象はGET/HEADのみ
  # ...（省略：オリジンリクエストポリシーやキャッシュポリシーの関連付け）
}

※CloudFrontでは一部メソッドだけ追加で許可できず、POSTを含める場合全HTTPメソッドを有効にする必要があります ￼。不要な操作はS3バケットポリシー側で拒否する方針です ￼。

	•	パスパターンのルーティング: /api/auth/*などNextAuthのAPIルートが確実にApp Runnerにフォワードされるよう、path_pattern = "/api/*"（または必要に応じさらに細分化）を定義済みか確認します。仮に抜けていれば上記のように優先度の高いビヘイビアを追加します。
	•	Hostヘッダの取り扱い: App Runnerオリジンには通常、ビューワのHostヘッダをそのまま渡さない設定が必要です。CloudFront推奨設定では、App Runnerにはオリジンのドメイン名をHostヘッダとして送ります ￼ ￼。TerraformではOrigin Request PolicyでHostを除外するか、Managed PolicyのAllViewerExceptHostHeaderを利用します。これによりApp Runnerが404を返す問題を防ぎます ￼。なお、Hostを除外してもブラウザにはCloudFront側のドメインで応答が返るため、Set-Cookieヘッダなどは引き続きブラウザのドメインに適用されます。
	•	APIレスポンスのキャッシュ禁止: 認証関連のAPI (/api/auth/*)はキャッシュさせない設定にします。NextAuthのメンテナーもCloudFront利用時には/api/auth/はキャッシュしないよう推奨しています ￼。Terraformでは対応するcache_policyでCache-Control: no-storeをオリジンから受け入れる、もしくは最初からmin_ttl = 0, default_ttl = 0で設定します。

以上の修正により、CloudFront経由でもNextAuthの認証API呼び出しが正常に通り、403エラーやリダイレクトループが解消されます。

S3バケットの公開設定とOACの問題

原因 (原理):
CloudFrontからS3へのアクセスが拒否され、_next/static/...jsなど静的アセットが403になる主因は、Origin Access Control (OAC) 周りの設定不備です。S3バケットをプライベートにした場合、CloudFront(OAC)にS3オブジェクト読み取り権限を与える必要があります ￼ ￼。これがバケットポリシーで許可されていなかったり、CloudFrontディストリビューションにOAC自体が紐付いていないと、CloudFrontからのGetObjectリクエストは**AccessDenied (403)**となります ￼ ￼。また、S3オブジェクトがKMS暗号化されている場合、CloudFrontにKMSキーの復号権限がないと同様にアクセス拒否されます ￼。

該当箇所:
TerraformのS3モジュール（terraform/modules/s3）およびCloudFrontモジュール内でのバケットポリシーとOAC設定が該当します。例えば、S3モジュールでaws_s3_bucket_policyがOACを許可しているか、CloudFrontモジュールでaws_cloudfront_origin_access_controlリソースを作成しディストリビューションのオリジンに関連付けているかを確認します。

修正方針:
	•	バケットポリシーの適切な設定: S3バケットポリシーにCloudFront(OAC)からのアクセス許可ステートメントを追加します。具体的には以下のような内容です ￼ ￼:

{
  "Sid": "AllowCloudFrontServicePrincipalReadOnly",
  "Effect": "Allow",
  "Principal": { "Service": "cloudfront.amazonaws.com" },
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::<バケット名>/*",
  "Condition": {
    "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::<AWSアカウントID>:distribution/<ディストリビューションID>"
    }
  }
}

Terraformでは、上記に相当するポリシーJSONを組み立ててaws_s3_bucket_policyに設定します。重要: AWS:SourceArnにCloudFrontのDistribution ARNを指定することで、その配信経由のアクセスに限定します ￼。

	•	OACの紐付け確認: CloudFrontディストリビューションのオリジン設定で、該当S3オリジンに対し作成済みのOAC IDを関連付けます（Terraformのaws_cloudfront_distributionのorigin.access_control_idプロパティなど）。または、TerraformでCloudFrontとS3モジュール間でOAC情報（例: OACのIDまたは名前）を渡し、CloudFrontリソース定義内でorigin_access_control_id = module.s3.oac_idのように設定されていることを確認します。
	•	Bucket Owner Enforcedの利用: 新しいバケットではObject Ownershipを「Bucket owner enforced」に設定し、ACLを無効化します ￼。Terraformでもaws_s3_bucketのbucket_owner_enforced = true（またはacl = nullでACL無効化）を設定します。これによりOAC経由のアクセス権限管理が一元化され、不要なパブリックアクセスは遮断されます。
	•	KMSキーの権限 (該当時のみ): 静的ファイルを格納するバケットでSSE-KMS暗号化を使っている場合、CloudFrontが該当キーで復号できるようキーのポリシーに許可を追加します ￼。キーのポリシーステートメントでPrincipal: {"Service": "cloudfront.amazonaws.com"}かつConditionで対象のDistributionを限定し、kms:Decrypt等を許可します。TerraformのKMSリソース定義（もしあれば）にポリシーを追記するか、後述のようにキーポリシーJSONを更新します。例:

{
  "Sid": "AllowCloudFrontSSEKMS",
  "Effect": "Allow",
  "Principal": { "Service": "cloudfront.amazonaws.com" },
  "Action": [ "kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*" ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::<AccountID>:distribution/<DistributionID>"
    }
  }
}


	•	デバッグポイント: 修正後も403が出る場合は、CloudFrontとS3のログを確認します。例えばCloudFrontアクセスログでx-edge-result-typeがAccessDeniedとなっているリクエストを洗い出し、バケットポリシー条件と一致しているか（二重にOAIとOACが混在していないか等）チェックします。

以上により、CloudFrontがOAC経由でS3上の_next/static/*ファイルにアクセス可能となり、403 Forbiddenエラーが解消されます。特にTerraform設定では、バケットポリシーとCloudFrontオリジン設定が意図通り噛み合っているか再度検証してください。

静的アセットのアップロード方法とビルドの一貫性の問題

原因 (原理):
Next.jsアプリの静的ビルド出力とCloudFront/S3へのデプロイ手順に不整合があると、クライアント側で必要なJSファイルが見つからずエラーや403の原因となります。例えば:
	•	デプロイ漏れやパス不一致: next build/exportで生成された_next/static/*や各ページのHTMLファイルが正しくS3にアップロードされていない場合、CloudFront経由のアクセスが存在しないオブジェクトに対し403/404を返します（存在しないキーへのアクセスはデフォルトではAccessDeniedを返しうる ￼ ￼）。特に**_next/*ディレクトリ**はNext.jsのバンドル資産を含みますが、Terraformではなくデプロイスクリプト（おそらくscripts/deploy.sh内）でS3に同期しているはずです。この同期処理でパスの階層やファイル権限がずれていないか確認が必要です。
	•	トレイリングスラッシュとインデックス: Next.jsの静的エクスポートでは、各ページはpage/index.html形式で出力されます。CloudFront経由でユーザーが/loginのように末尾スラッシュなしでアクセスした場合、S3上loginキーが見つからずエラーとなる可能性があります ￼ ￼。本構成ではS3をウェブサイトホスティングモードではなくCloudFront+OACで使っているため、自動でindex.htmlを解決しません。このためカスタムエラーページ設定で403/404時に/index.html（または各アプリのルート）にフォールバックする設定を入れているようですが ￼、それが意図通り機能していない可能性があります。特に複数SPAをパス別にホスティングしている場合、フォールバック先を適切に振り分けないと誤ったページにリダイレクトされます。
	•	ビルドの同期性: Next.jsアプリケーションの静的ファイルとApp Runner上のAPIが同じコードベースからビルドされているか確認が必要です。例えば、CIフローで静的エクスポートした後に別のソースからDockerイメージをビルドしていたり、タグlatestの指す内容がずれていると、静的側と動的側でバージョン不一致が生じます。これにより、静的ファイル名（ハッシュ）やAPI仕様が嚙み合わず、不正なリダイレクトやエラーを招きます。

該当箇所:
リポジトリ内のデプロイスクリプト（scripts/quick-deploy.shやdeploy.sh）およびフロントエンドビルド設定（frontendサブモジュール側のNext.js設定）に注目します。Terraformではなく、CI/CDの処理やS3アップロードコマンド（例: aws s3 sync）が問題の箇所です。また、Next.jsのnext.config.jsでtrailingSlash設定やassetPrefixを使用している場合、その値とCloudFrontパスの対応もチェックします。

修正方針:
	•	静的ファイルの完全デプロイ: ビルド後に生成されるout/（next export出力）または.nextフォルダ内のstatic資産が全てS3にアップロードされているか確認します。Terraformでバケットバージョニングやライフサイクルが有効な場合でも、基本的にaws s3 syncコマンドで不足なく転送されるはずです。例えばデプロイスクリプトで:

aws s3 sync ./frontend/out s3://<バケット名> --delete

のように削除と追加を適切に行っているか確認し、もし漏れがあれば追加します。--deleteオプションを付与して古いアセットを消し、新ビルドと不整合を残さないことも重要です。

	•	パスとCDNキャッシュの検証: _next/static/配下のファイルにブラウザから直接アクセスして403/404にならないかテストします（リポジトリにはtest-endpoints.shもあるようなので活用します）。403が出る場合は前述のOAC設定を、404が出る場合はファイルパスのずれ（例: CloudFrontのオリジンパス設定やterraform/modules/cloudfront内でのorigin.domain_name誤りなど）を疑います。CloudFrontのorigin.path設定を利用している場合、それに合わせてS3転送元ディレクトリを変更する必要があります。
	•	インデックスページのリダイレクト: SPAのルーティングで直URLアクセス時に404/403となる問題は、CloudFrontのカスタムエラーページ設定でカバーできます。しかしNext.jsを用いた複数SPA構成では、一律に/index.htmlへリダイレクトすると不都合です。TerraformのCloudFrontモジュールで、例えばエラーコード403,404に対し各アプリ配下のindex.htmlにフォールバックする設定が可能か検討します。単一SPAなら:

custom_error_response {
  error_code = 404
  response_code = 200
  response_page_path = "/index.html"
}

のように設定しますが、マルチSPAの場合はパス別ディストリビューションを分けるか、Lambda@Edge/CloudFront Functionsでパスを補完する方法も考えられます ￼。まずはNext.js側での対応として、next.config.jsにtrailingSlash: trueを設定しビルドし直すことで、/page/index.htmlではなく/page.htmlというファイルを出力する運用も検討します（ただし今回の構成ではindex.html形式でもCloudFrontでの対応が可能なため、どちらか一方に揃えることが重要です）。

	•	ビルド処理の一貫性: TerraformでECRリポジトリを用意しApp Runnerにデプロイしていますが、同じソースからのビルドであることを保証します。例えば、deploy.sh dev latest実行時にGitの最新コミットIDでフロントエンドをエクスポートし、同じコミットのコードでDockerビルドしているか検証します。frontendがサブモジュールになっているので、サブモジュールのバージョン差異にも注意が必要です。CI上でgit submodule update --init --remoteなどを忘れず、frontend側の変更がinfra側に反映されていることを確かめます。
	•	キャッシュ無効化: CloudFrontのキャッシュが古い静的ファイルを参照していると、新ビルド後も404が続く場合があります。本プロジェクトではデプロイ時にaws cloudfront create-invalidationを自動実行しているようですが ￼、念のためInvalidationパスが適切か確認します（例: /* 全無効化か、/_next/*のみ等）。不安であれば一律/*を指定する運用にして問題解消を優先します。

以上を実施し、静的アセットが確実に最新版に置き換わり、CloudFrontから正常に取得できるようにします。これにより_next/static/...の403/404エラーは解消され、ビルド不整合による動作不良も改善されます。

NextAuth.jsのCookie設定とCORSに関する問題

原因 (原理):
CloudFront + App Runner環境下でNextAuth.jsの認証セッションが維持できずログインループになるのは、クッキーとドメイン/ヘッダの取り扱いによるものです。具体的には:
	•	HostヘッダとコールバックURL: 前述のようにCloudFrontからApp RunnerへのリクエストではHostヘッダを書き換えており、Next.js側で認識するホスト名が実際のユーザアクセスドメインと異なります ￼。NextAuth.jsはNEXTAUTH_URL環境変数かリクエストのホストから認証用URLを組み立てます。これがズレると、認証フロー中のリダイレクト先やCookieドメインが噛み合わず、ログイン後に正しく遷移しません。
	•	Cookieの転送とSameSite: CloudFrontのオリジンリクエストポリシーでCookieヘッダを動的オリジンに転送していない場合、App Runner側のNextAuth APIがセッションクッキーを受け取れません。結果として常に未認証扱いとなり、ログインページに戻されます。ブラウザにはクッキーが設定されていても、CloudFront経由でそれが無視されれば、バックエンドではログインが維持されない状況です ￼。
	•	CSRFトークン不一致: NextAuth.jsのCredentialsプロバイダ等を使う場合、ログインフォーム送信にはCSRFトークンが必要です。通常NextAuthはサーバレンダリングでフォームに埋め込みますが、今回の/loginページが静的出力だとビルド時の古いCSRFトークンが埋め込まれてしまいます。これではApp Runner上の認証APIが受け取るトークンと合致せず、ログインが拒否され再度サインインページに戻されます。URLに?だけ付いてリロードされるのは、おそらくNextAuthがエラークエリ（例えば?error=CredentialsSignin等）を付与しリダイレクトしているためです。

該当箇所:
App Runnerのサービス設定（Terraformのterraform/modules/app-runner）で定義している環境変数やポート、CORS構設定が該当します。NextAuth.jsの設定ファイル（[...nextauth].ts）およびNext.jsのnext.config.jsも確認ポイントです。Cookieに関してはNextAuthのデフォルトではsameSite: Laxでドメインはホストと同一に設定されるため、本ケースでは主にヘッダと環境変数側の問題と推測されます。

修正方針:
	•	NEXTAUTH_URLの設定: App Runnerにデプロイするコンテナ環境に、NEXTAUTH_URLをCloudFront経由の本番URL（例: https://<CloudFrontドメイン名>）で設定します ￼。TerraformのApp Runnerモジュールでenvironment_variableとして追加し、terraform/environments/prod/terraform.tfvarsなどで実値を指定します。これによりNextAuthは自身の動作URLを正しく認識し、CSRFトークンの生成やコールバックURLにその値を用いるようになります。

# terraform/modules/app-runner/main.tf の一部
resource "aws_apprunner_service" "this" {
  # ...他の設定...
  environment_variables = {
    "NEXTAUTH_URL" = "https://${var.cloudfront_domain_name}"  # CloudFrontのURL
    "NEXTAUTH_SECRET" = var.nextauth_secret  # 共有シークレット
    # 他必要な環境変数...
  }
}


	•	Cookieヘッダの転送: CloudFrontのオリジンリクエストポリシーでCookieをApp Runnerに転送するようにします。Terraformではaws_cloudfront_origin_request_policyリソースでcookies_config = { cookie_behavior = "all" }を指定し、それを/api/*ビヘイビアに関連付けます（もしくはAWS管理ポリシーManaged-AllViewerを流用しつつHostだけ除外する形も可）。これにより、ログイン後ブラウザにセットされたnext-auth.session-token等のクッキーが、後続のAPIリクエスト（例えばセッション取得や認証チェック）でもApp Runnerに届き、セッションが維持されます ￼。
	•	CORS設定: NextAuth.jsは通常、SameSite=Laxクッキーの範囲で動くため、特別なCORSヘッダ設定は不要です（同一ドメイン上でリダイレクトやフォーム送信するため）。ただし、もし今後フロントエンドがCloudFrontドメインとは別のカスタムドメインを持ちApp Runner APIと通信するようなケースでは、App Runner側でAccess-Control-Allow-Origin等を設定する必要があります。TerraformではApp RunnerにALB経由のカスタムドメインマッピングも可能ですが、本ケースでは採用していません。現在はCloudFrontを経由しているためCORS問題は表面化しない想定ですが、念のためブラウザのコンソールでCORSエラーが出ていないか確認します。
	•	認証ページの扱い: Next.jsのログインページを動的ページとして扱うことも検討します。/loginページを静的エクスポートから除外し（例えばgetServerSidePropsを使う等）、CloudFront経由でもApp Runnerから動的提供させれば、NextAuthが埋め込むCSRFトークンが常に新鮮な状態となり、認証成功率が上がります。Terraform設定自体は変えずに、フロントエンド実装上の対応になります。この変更が難しい場合、少なくとも静的ログインページがロード時にCSRFトークンを取得する仕組みを入れます。例えばNextAuthが提供する/api/auth/csrfエンドポイントに対し、クライアント側でトークンをフェッチしてフォームに埋め込む処理を追加します。
	•	セッションクッキー設定: 必要に応じてNextAuthのオプションでuseSecureCookies: trueを確認します（デフォルトで本番httpsではtrue）。さらに、マルチSPAでサブドメインを跨いでセッション共有をする場合はcookie.domainを設定することになりますが、今回は同一ドメイン配下の想定なので不要です。

以上の変更により、ログインボタン押下→?付きで/loginに戻されるループは解消されるはずです。CloudFront配下でもNextAuthのセッションCookieが正しく扱われ、ユーザは一度のログインで目的のページに遷移できます。

まとめ

各種設定を修正後は、再度Terraformを適用し、./scripts/quick-deploy.sh full prodなどでインフラ・アプリ・静的ファイルを同期的に再デプロイしてください。CloudFront経由の動作確認では、認証フローが期待通り進行すること（ログイン後にリダイレクトループしない）、および開発者ツールのネットワークタブで静的ファイルがすべて200 OKで応答していることをチェックします。これら対応によって、CloudFront・S3・App Runner・Next.js・NextAuth.jsから成るマルチSPA環境で発生していた不具合は概ね解決されるでしょう。

参考: 類似構成におけるCloudFrontと認証の課題は他社でも指摘されており、「CloudFront側で認証APIをキャッシュしない」「すべての必要ヘッダ（Cookie等）をオリジンに伝搬する」ことが成功のポイントです ￼。また、CloudFront⇔S3のプライベート連携にはOACとバケットポリシーを正しく組み合わせる必要があります ￼。設定見直しの際は公式ドキュメントやベストプラクティスも都度参照しつつ進めてください。各修正箇所のコード変更例は上記の通りで、TerraformモジュールとNext.jsアプリ設定の双方を調整することで問題の根本解決に至ります。