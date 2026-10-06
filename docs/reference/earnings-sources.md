# Register earnings listing sources

Use the existing analysis-target registry to configure earnings sources. First register or select a target with `/api/targets`; index membership is optional. Review the publisher's acquisition and preservation conditions before registering or enabling a source. Lens has no approval state or automatic terms assessment.

| Method | Path | Result |
| --- | --- | --- |
| `POST` | `/api/targets/:target_id/earnings-sources` | Register a source (`201`) |
| `GET` | `/api/targets/:target_id/earnings-sources` | List all sources, including disabled sources (`200`) |
| `GET` | `/api/targets/:target_id/earnings-sources/:id` | Inspect a source (`200`) |
| `PATCH` | `/api/targets/:target_id/earnings-sources/:id` | Change its listing URL or enablement (`200`) |

Send attributes in a `source` object. The target ID is supplied by the path, not the body. Registration requires only `listing_url`; `enabled` defaults to `true` when omitted. Explicit `false` registers a disabled source. For example:

```json
{"source":{"listing_url":"https://publisher.example/ir/results","enabled":false}}
```

A source response contains `source` with `id`, `target_id`, `listing_url` and `enabled`. A list response contains a `sources` array. Each target can have multiple sources, such as separate results and correction listings. Source enablement is independent of the target's `active` flag and index memberships. Target registration alone creates no source. Neither registration nor enabling a source starts a crawl; collector integration is tracked in [#125](https://github.com/9renpoto/lens/issues/125).

Use `{"source":{"enabled":false}}` to stop eligibility for collection. A partial update preserves omitted fields; `{"source":{}}` is a no-op. The source ID and target remain fixed while the URL changes. Register a new source for a different target. There is no deletion endpoint.

## Validation

- The target must already exist. An unknown or malformed target/source ID, or a source belonging to a different target, returns `404` with `{"error":"not_found"}`.
- `listing_url` must be an absolute HTTP(S) URL with a nonempty host, no credentials, whitespace, control characters or fragment, and at most 2048 UTF-8 bytes. The byte limit also keeps the full-URL uniqueness index within PostgreSQL's index entry bound. Paths ending in `.pdf` (case insensitive, after percent decoding) are rejected as direct-document URLs. URL validation does not fetch the page or prove that its content is a listing; operators select the listing page.
- Within one target, an exactly matching URL is unique. Registration and URL updates reject duplicates; different targets may use the same URL. URLs are not canonicalized or silently rewritten.
- Missing required attributes, explicit null/blank URL or enablement, invalid boolean values, non-object/missing `source`, and a body containing `target_id` return `422` with field errors in `errors`. Fields omitted from updates retain their values. No PDF settings, document category, source display name or approval fields are required.

## Migration and compatibility

Apply the new migrations with `mix ecto.migrate` before serving the API. `20261006000000` creates `earnings_sources` with a restricted target foreign key, per-target URL uniqueness and enabled-by-default rows. It imports no fixed-catalog sources and creates no targets. Operators register their chosen targets and sources manually, including any former pilot routes they want to retain.

`20261006000100` replaces the former three-issuer restriction in `earnings_http_check_bounds` with a nonblank issuer code of 1–50 characters. Request counts, HTTP status and PDF/listing byte caps remain enforced. It changes no existing original, acquisition, HTTP check or assessment rows, and preserves the existing immutability triggers. Historical checks need no registered source. `HTTPHistory.record/1` retains its existing input/result contract, including persistence retries for previous issuer codes. Source changes do not relabel historical URLs or issuers.

The whitelist removal is forward-only: rolling it back could reject new issuer history. Its `down` migration fails explicitly rather than deleting history or reinstalling an incompatible constraint. Use a coordinated pre-migration backup if restoring the old schema is necessary.

The existing `/api/sources` feed API and `/api/targets` responses retain their contracts. The new earnings endpoints are separate from feed sources. `SourceCatalog.all/0` now reads registered sources and current target names; `all(enabled_only: true)` filters only by source enablement. `for_issuer/1` returns all routes; `fetch/1` returns a single route, `:unsupported_issuer` when none exist, or `:multiple_sources` when ambiguous. The obsolete fixed host/path helper `document_url_allowed?/2` is removed. Source registration is not a document URL permission policy: the HTTP transport still requires an explicit `allowed_url?` predicate for the initial URL and each redirect. Registered-source crawling and its external-host policy belong to #125. The current fixed-issuer document classifier is separate work in [#127](https://github.com/9renpoto/lens/issues/127).

## Verification

The API tests cover a synthetic `7203` target outside the former three-company set, with no membership and `active: false`, multiple routes, defaults, explicit false, partial updates, duplicate rejection, target isolation and URL validation. Existing feed/target controller tests cover their client contracts. HTTP history tests exercise non-pilot listing/PDF checks and retained bounds.

Run the forward-migration check against an empty disposable database:

```sh
MIX_ENV=test POSTGRES_DB=lens_source_migration_check mix ecto.create
MIX_ENV=test POSTGRES_DB=lens_source_migration_check mix run --no-start test/system/earnings_source_migration_check.exs
```

The check seeds old-schema successes and a failure, compares all prior original/acquisition/check/target rows after migration, verifies no automatic source import, changes source settings without changing history, tests existing persistence callers and new issuers, and checks retained history immutability. These deterministic checks do not establish live publisher access or local k3s deployment verification; that broader workflow belongs to [#131](https://github.com/9renpoto/lens/issues/131).

<details>
<summary>日本語</summary>

# 決算資料の一覧取得先を登録する

既存の分析対象台帳を使って決算取得先を設定する。まず`/api/targets`で対象を登録または選択する。指数所属は任意。有効な取得先を登録または有効化する前に、発行元の取得・保存条件を確認する。Lensに承認状態や利用条件の自動判定はない。

| メソッド | パス | 結果 |
| --- | --- | --- |
| `POST` | `/api/targets/:target_id/earnings-sources` | 取得先を登録（`201`） |
| `GET` | `/api/targets/:target_id/earnings-sources` | 無効な取得先を含む全取得先の一覧（`200`） |
| `GET` | `/api/targets/:target_id/earnings-sources/:id` | 取得先の詳細（`200`） |
| `PATCH` | `/api/targets/:target_id/earnings-sources/:id` | 一覧URLまたは有効状態を変更（`200`） |

属性は`source`オブジェクトに入れる。対象IDは本文ではなくパスで指定する。登録に必要なのは`listing_url`のみで、`enabled`の省略時は`true`。明示的な`false`で無効な取得先を登録できる。例：

```json
{"source":{"listing_url":"https://publisher.example/ir/results","enabled":false}}
```

取得先の応答は`source`内に`id`・`target_id`・`listing_url`・`enabled`を含む。一覧応答は`sources`配列を含む。短信と訂正の別一覧など、対象ごとに複数の取得先を登録できる。有効状態は対象の`active`や指数所属と独立する。対象登録だけでは取得先を作成しない。取得先登録や有効化ではクローリングを開始しない。収集処理との統合は[#125](https://github.com/9renpoto/lens/issues/125)で扱う。

収集対象から外すには`{"source":{"enabled":false}}`を送る。部分更新では省略した項目を維持し、`{"source":{}}`は何も変更しない。URLを変更しても取得先IDと対象は固定する。別の対象には新しい取得先を登録する。削除エンドポイントはない。

## 検証規則

- 対象は登録済みであること。不明・不正な対象／取得先IDや、別の対象に属する取得先には、`{"error":"not_found"}`と`404`を返す。
- `listing_url`は空でないホストを持つHTTP(S)の絶対URLとし、認証情報・空白・制御文字・フラグメントを含まず、UTF-8で2048バイト以内とする。バイト上限により完全なURLの一意性インデックスもPostgreSQLのインデックス項目上限に収まる。パスが`.pdf`で終わるURLは、大文字小文字を区別せずパーセント復号後に判定し、資料への直接URLとして拒否する。URL検証ではページを取得せず、内容が一覧であることも証明しない。運用者が一覧ページを選ぶ。
- 同じ対象内で完全一致するURLは一意とする。登録時とURL更新時に重複を拒否し、別の対象では同じURLを使える。URLの正規化や黙った書き換えはしない。
- 必須属性の不足、URL・有効状態への明示的なnull／空文字、不正な真偽値、オブジェクトでない／欠落した`source`、本文内の`target_id`には、`errors`内の項目エラーと`422`を返す。更新時の省略項目は維持する。PDF設定・資料種類・取得先固有の表示名・承認項目は必須にしない。

## 移行と互換性

APIを提供する前に`mix ecto.migrate`で追加マイグレーションを適用する。`20261006000000`は削除制限付きの対象外部キー、対象ごとのURL一意性、有効が既定の行を持つ`earnings_sources`を作成する。固定台帳の取得先を取り込まず、対象も作成しない。従来のパイロット経路を引き続き使う場合も含め、運用者が選んだ対象と取得先を手動登録する。

`20261006000100`は`earnings_http_check_bounds`の固定3社制限を、空白だけではない1〜50文字の企業コードに置き換える。リクエスト回数・HTTPステータス・PDF／一覧のバイト上限は維持する。既存原本・取得・HTTP確認・判定の行を変更せず、既存の履歴変更禁止トリガーを維持する。過去の確認履歴には取得先登録を要求しない。`HTTPHistory.record/1`の既存入力・結果契約を保持し、以前の企業コードでの保存再試行にも対応する。取得先変更で過去のURLや企業を付け替えない。

企業制限の解除は前進専用とする。戻すと新しい企業の履歴を拒否し得るため、`down`マイグレーションは履歴削除や互換性のない制約の復元を行わず、明示的に失敗する。旧スキーマへの復元が必要なら、移行前の整合したバックアップを使う。

既存のフィードAPI `/api/sources`と`/api/targets`応答の契約を維持する。新しい決算エンドポイントはフィード取得先とは別。`SourceCatalog.all/0`は登録した取得先と現在の対象名を読み、`all(enabled_only: true)`は取得先の有効状態だけで絞る。`for_issuer/1`は全経路を返す。`fetch/1`は1経路ならそれを返し、0件なら`:unsupported_issuer`、複数なら`:multiple_sources`を返す。固定のホスト・パス用の古い関数`document_url_allowed?/2`は削除する。取得先登録は資料URLの許可ポリシーではない。HTTP取得には引き続き初期URLと各リダイレクト先に適用する明示的な`allowed_url?`判定が必要。登録取得先のクローリングと外部ホストのポリシーは#125で扱う。現行の固定企業用の資料判定器は[#127](https://github.com/9renpoto/lens/issues/127)の別作業。

## 検証

APIテストでは従来の固定3社外の合成対象`7203`を使い、所属なし・`active: false`、複数経路、既定値、明示的なfalse、部分更新、重複拒否、対象の分離、URL検証を確認する。既存のフィード／対象コントローラテストで既存クライアントの契約を確認する。HTTP履歴テストでは固定3社外の一覧／PDF確認と維持した上限を検証する。

空の使い捨てDBで追加マイグレーションの検証を実行する：

```sh
MIX_ENV=test POSTGRES_DB=lens_source_migration_check mix ecto.create
MIX_ENV=test POSTGRES_DB=lens_source_migration_check mix run --no-start test/system/earnings_source_migration_check.exs
```

旧スキーマに成功と失敗の記録を作り、移行後に既存の原本／取得／確認／対象の全行を比較する。自動取得先取り込みがないこと、設定変更で履歴が変わらないこと、既存の保存呼び出しと新しい企業、履歴の変更禁止を確認する。この再現可能な検証は実サイトへのアクセスやローカルk3sでの実環境検証を証明しない。その広いフローは[#131](https://github.com/9renpoto/lens/issues/131)で扱う。

</details>
