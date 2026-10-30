# Earnings subscription discovery

Register a feed with `POST /api/sources` and set `ingestion_mode` to
`earnings_updates`. The default `document` mode indexes feed text as before.
`endpoint_url` is a publisher feed or RSSHub feed endpoint; `feed_format`,
`acquisition_kind` and `publisher_authority` remain independent classifications.
RSSHub does not establish publisher authority or a financial release identity.
Use `enabled` and `poll_interval_seconds` to control the existing scheduler.
The same discovery path is available through `mix lens.ingest SOURCE_ID`.

The first complete successful response records `feed_baselined_at` and item
fingerprints, including for an empty feed. Existing items produce no update
signals or searchable documents. No conditional validators are sent until the
baseline exists, and an unexpected initial 304 is a failure. Failed fetches and
malformed feeds do not establish or advance the baseline.

Later polls emit new items and feed-visible changes. An item is identified by
its nonblank feed ID/GUID, or by its URL when no ID exists, scoped to the source.
An item without either is rejected. Conflicting duplicate IDs are isolated;
identical repetitions do not create multiple signals. Persisted fingerprints
prevent unchanged rereads and reappearing items from being emitted again after
an application restart. Feed-visible XML changes, including attachment changes,
are compared before text normalization removes markup. Formatting changes can
therefore also produce an update signal.

RSS enclosures, Atom enclosure links and body hyperlinks remain available as
resolved references. Atom and RSS XML Base values are respected at the feed and
entry level; body/enclosure XML Base values are used for their references.
The detector never fetches those references to discover changes. A PDF replaced
without a corresponding feed change is invisible, and items disappearing
between polls may be missed.

`Lens.Ingestion.ingest/2` returns signals in `Result.update_signals`. After the
baseline/item-state transaction commits, each signal is also broadcast on
`Lens.PubSub` topic `earnings_feed_updates` as `{:earnings_feed_update, signal}`.
The signal has `source_id`, a source-scoped hashed `item_key`, `change` (`:new`
or `:changed`) and the parsed `entry`. The entry includes the item ID, canonical
URL, title, normalized content, raw feed content, author, publication/update
dates, `attachments` (`url` and `type`), `body_links` and a feed fingerprint.
Keep these signals and source references inside the private application boundary.

Signals are best-effort handoffs, not a durable work queue. A crash after state
commit can lose a notification; missing subscribers do not cause replay.
Fingerprints record discovery, not material-processing success. After detection, the built-in [material acquisition](earnings-materials.md) stage
uses the source's explicit material policy, retaining derived HTML text/provenance
and verified PDFs without storing HTML originals. Non-empty derived HTML and PDF
text is indexed as `feed_material` search results without inferring a release
identity. `provenance_url` points to `GET /api/feed-materials/:id`, which returns
extracted text, material references and the retained PDF original ID when present. Each successful
material is currently returned separately; revision selection is tracked in #237.
Failures are reported through Sentry and do not stop independent materials. Reading
the existing output RSS does not start discovery. No failed-material retry or
replay is implemented.

`PATCH /api/sources/:id` can change the mode or endpoint. Either change clears
the baseline, fingerprints and conditional validators transactionally; the next
successful full response becomes a fresh baseline. Title, enablement and polling
interval edits preserve the baseline. `feed_baselined_at` is read-only in the API.

Discovery failures use the [sanitized Sentry interface](ingestion-errors.md).
Expected failures and exceptions return a failure result without blocking other
sources. Failure counts and attempt times support scheduling, while earnings
mode keeps `last_error` empty rather than storing error details in PostgreSQL.
The current schema includes discovery state and material extraction indexes;
recreate disposable databases when the fingerprint differs, following
[development setup](../development.md).

<details>
<summary>日本語</summary>

# 決算購読の更新検知

`POST /api/sources`でフィードを登録し、`ingestion_mode`を`earnings_updates`に設定する。
既定の`document`モードは従来どおりフィード本文を検索登録する。`endpoint_url`は公開元
フィードまたはRSSHubフィードのエンドポイントとし、`feed_format`・`acquisition_kind`・
`publisher_authority`は独立した分類を維持する。RSSHubであることは公開元の権威性や
決算リリースの識別を確定しない。`enabled`・`poll_interval_seconds`で既存スケジューラを
制御する。`mix lens.ingest SOURCE_ID`からも同じ更新検知を利用できる。

最初の完全な正常応答で`feed_baselined_at`と項目のfingerprintを記録し、空のフィードも
基準とする。既存項目から更新情報や検索可能な文書は作らない。基準作成までは条件付き取得の
validatorを送らず、想定外の初回304は失敗とする。取得失敗・不正なフィードでは基準を
作成・更新しない。

以後は新着とフィード上の変更を通知する。項目は空でないフィードID／GUID、なければURLで、
取得先ごとに識別する。いずれもない項目は拒否する。矛盾する重複IDは分離し、同じ内容の反復で
複数通知を作らない。永続化したfingerprintにより、再起動後も変更なしの再取得や再登場を
再通知しない。添付変更を含むフィード上のXML変更は本文正規化でマークアップが失われる前に
比較するため、書式変更も更新情報となる場合がある。

RSS enclosure・Atom enclosureリンク・本文中のリンクを解決済み参照として保持する。
Atom・RSSのフィードと項目レベルのXML Base、および本文・enclosureのXML Baseを参照解決に
使う。変更検知のために参照先を取得しない。対応するフィード変更がないPDF差し替えは検知せず、
確認の間に消えた項目は見落とす場合がある。

`Lens.Ingestion.ingest/2`は`Result.update_signals`へ更新情報を返す。基準・項目状態の
トランザクションがコミットされた後、`Lens.PubSub`の`earnings_feed_updates`トピックにも
`{:earnings_feed_update, signal}`を配信する。signalは`source_id`、取得先内で識別する
ハッシュ化済み`item_key`、`change`（`:new`または`:changed`）、解析済み`entry`を持つ。
entryには項目ID・canonical URL・表題・正規化本文・生のフィード本文・著者・公開／更新日時・
`attachments`（`url`と`type`）・`body_links`・フィードfingerprintを含める。
これらの更新情報と取得先参照はアプリの非公開境界内で扱う。

通知はbest-effortの受け渡しであり、永続的な作業キューではない。状態コミット後のクラッシュで
通知を失う場合があり、購読する処理が不在でも再配信しない。fingerprintは更新の発見を示し、
資料処理の成功を示さない。検知後は組み込みの[資料取得](earnings-materials.md)処理が明示的な取得ポリシーを使用し、
HTML原本を保存せずHTML抽出本文・出典情報と検証済みPDFを保持する。空でないHTML・PDFの
抽出本文は、リリースの識別を推測せず`feed_material`として検索登録する。`provenance_url`の
`GET /api/feed-materials/:id`は抽出本文・資料参照と、存在する場合は保持済みPDF原本IDを返す。
現在は成功した資料ごとに検索結果を返し、改訂版の選択は#237で扱う。失敗はSentryに報告し、
独立した他の資料の処理を妨げない。既存の出力RSSを読んでも更新検知を開始しない。
失敗資料の再試行・再処理は実装しない。

`PATCH /api/sources/:id`でモードまたはendpointを変更できる。いずれの変更も基準・
fingerprint・条件付き取得のvalidatorをトランザクションで消去し、次の正常な完全応答を
新たな基準とする。表題・有効状態・確認間隔の変更では基準を維持する。
APIの`feed_baselined_at`は読み取り専用とする。

更新検知の失敗は[匿名化済みSentryインターフェース](ingestion-errors.md)へ報告する。
想定済みの失敗と例外は、他の取得先を妨げず失敗結果を返す。失敗回数・試行日時はスケジュールに
使用し、決算モードの`last_error`は空のままとしてPostgreSQLへエラー詳細を保存しない。
現行スキーマは検知状態と資料抽出の検索インデックスを含むため、fingerprintが異なる破棄可能DBは
[開発手順](../development.md)に従って再作成する。

</details>
