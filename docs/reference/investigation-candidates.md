# Investigation candidates and RSS

Lens accepts manually authored investigation candidates and immediately exposes them through one unauthenticated local RSS 2.0 feed. This verifies the notification-source boundary in [ADR 0014](../adr/0014-publish-manual-investigation-candidates-through-rss.md). Use the prototype inside the application's existing private access boundary.

## Register a candidate

After `mix ecto.migrate` and starting Lens locally, register a candidate:

```sh
curl --fail-with-body http://127.0.0.1:4000/api/investigation-candidates \
  -H 'Content-Type: application/json' \
  -d '{"candidate":{"title":"Investigate the margin change","body":"Compare the disclosed change with the previous period.","details_url":"https://example.com/evidence","published_at":"2026-10-21T00:30:00Z"}}'
```

The API returns HTTP 201 with a `candidate` object containing the server-assigned UUID and registered fields. Invalid attributes or a missing/non-object `candidate` return HTTP 422 with `errors`.

| Field | Contract |
|---|---|
| `title` | Required nonblank text, at most 255 Unicode codepoints. |
| `body` | Required nonblank plain text, at most 4000 Unicode codepoints. |
| `details_url` | Optional absolute HTTP(S) URL without credentials or whitespace, at most 2048 Unicode codepoints. Omitted, null or blank means no link. |
| `published_at` | Required ISO 8601 datetime with a timezone; stored as UTC. Publication metadata, not a scheduling instruction: registration publishes immediately. |

Text must contain only XML 1.0 characters. Client-supplied IDs are ignored. Every successful registration creates a new identity, including repeated requests with identical fields. There is no request deduplication, editing or deletion API. Register corrections as separate candidates.

## Read the feed

`GET /feeds/investigation-candidates.rss` returns `application/rss+xml` with `Cache-Control: no-store`. All registered candidates appear in descending publication-time order, with UUID as a stable tie-breaker. There is no feed window or pagination in this prototype.

Each item contains `guid` (`urn:uuid:<candidate-id>`, `isPermaLink="false"`), `title`, an HTML-escaped plain-text `description`, and an RFC 822 `pubDate` in GMT with second precision. `link` appears only when a details URL exists. IDs and content remain stable across reads and application restarts. Consumers should compare GUIDs to detect new items, rather than relying on timestamps or list position.

## Verify local consumer detection with Elixir

Use a disposable local database: this check registers one synthetic candidate and leaves it available in the feed. With Lens running in another terminal:

```sh
mix run --no-start scripts/check_investigation_feed.exs http://127.0.0.1:4000
```

The script uses existing `Req` and `Lens.Ingestion.Parser` to observe the feed before registration, register a candidate through HTTP, detect exactly one new GUID, and verify repeated reads. Erlang/OTP's `:xmerl` independently parses the XML and checks channel metadata and item fields. No extra package or Python runtime is required. This demonstrates local RSS publication and consumer detection; downstream services and delivery to a person are outside this check.

<details>
<summary>日本語</summary>

# 調査候補とRSS

Lensは手動作成の調査候補を受け付け、認証なしのローカル単一RSS 2.0フィードへ即時公開する。[ADR 0014](../adr/0014-publish-manual-investigation-candidates-through-rss.md)の通知元の境界を検証する。プロトタイプはアプリの既存の非公開アクセス境界内で使う。

## 候補の登録

`mix ecto.migrate`を実行してLensをローカル起動後、候補を登録する。

```sh
curl --fail-with-body http://127.0.0.1:4000/api/investigation-candidates \
  -H 'Content-Type: application/json' \
  -d '{"candidate":{"title":"Investigate the margin change","body":"Compare the disclosed change with the previous period.","details_url":"https://example.com/evidence","published_at":"2026-10-21T00:30:00Z"}}'
```

APIはサーバーが割り当てたUUIDと登録フィールドを含む`candidate`オブジェクトをHTTP 201で返す。属性が不正、または`candidate`が未指定・オブジェクト以外の場合、`errors`をHTTP 422で返す。

| フィールド | 契約 |
|---|---|
| `title` | 必須の空白以外を含むテキスト。Unicodeコードポイントで最大255文字。 |
| `body` | 必須の空白以外を含むプレーンテキスト。Unicodeコードポイントで最大4000文字。 |
| `details_url` | 任意の認証情報・空白なし絶対HTTP(S) URL。Unicodeコードポイントで最大2048文字。省略、null、空白のみの場合はリンクなし。 |
| `published_at` | 必須のタイムゾーン付きISO 8601日時。UTCで保存する。公開日時のメタデータであり、予約公開の指示ではなく登録時に即時公開する。 |

テキストはXML 1.0で許可された文字のみとする。クライアント指定のIDは無視する。同じフィールドを繰り返し送った場合も、成功した登録ごとに新しい識別子を作る。リクエストの重複排除、編集・削除APIはない。訂正は別候補として登録する。

## フィードの取得

`GET /feeds/investigation-candidates.rss`は`application/rss+xml`と`Cache-Control: no-store`を返す。すべての登録済み候補を公開日時の降順で表示し、同時刻の場合はUUIDで安定した順序にする。このプロトタイプには取得期間の制限やページ分割はない。

各項目は`guid`（`urn:uuid:<candidate-id>`、`isPermaLink="false"`）、`title`、プレーンテキストをHTMLエスケープした`description`、秒精度のGMTによるRFC 822形式の`pubDate`を含む。詳細URLがある場合だけ`link`を付ける。IDと内容は反復取得・アプリ再起動を通じて維持する。購読側は日時や一覧の位置に頼らず、GUIDを比較して新着を検出する。

## Elixirでローカル購読側の検出を確認する

破棄可能なローカルDBを使う。この検証は合成候補を1件登録し、フィードで取得可能な状態に残す。別ターミナルでLensを起動した状態で実行する。

```sh
mix run --no-start scripts/check_investigation_feed.exs http://127.0.0.1:4000
```

スクリプトは既存の`Req`と`Lens.Ingestion.Parser`を使い、登録前のフィードを観測し、HTTPから候補を登録し、新しいGUIDをちょうど1件検出して反復取得を検証する。Erlang/OTPの`:xmerl`でXMLを独立に解析し、チャネル情報と項目のフィールドも確認する。追加パッケージやPythonランタイムは不要。この検証はローカルRSS公開と購読側の検出を示し、後続サービスや人への通知到達は対象外とする。

</details>
