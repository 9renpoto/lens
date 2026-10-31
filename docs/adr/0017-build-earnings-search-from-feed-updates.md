---
status: accepted
---

# Build earnings search from feed updates

Use publisher RSS or RSSHub feeds to detect updates to operator-selected earnings
subscriptions. A feed supplies update signals and references to source material;
it does not establish that its content is sufficient for analysis. Automatically
acquire the corresponding page body and PDF attachments, extract their text and
add successful results to the search database. This keeps discovery independent
of the amount of text a publisher includes in its feed.
Track implementation scope in [#232](https://github.com/9renpoto/lens/issues/232).

## Discovery boundary

Use the first successful feed read as a baseline without acquiring or indexing
its existing items. Process subsequent new items and changes visible in the
feed. Preserve the baseline and observed item identity/content across application
restarts so ordinary polling does not repeatedly acquire unchanged material.
Feed visibility bounds detection: a change only to a linked page or attachment
is not detected unless the feed exposes a corresponding change. Do not promise
complete discovery of items that disappear between polls.

Start with sources supported by publisher feeds or RSSHub routes. Lens owns
polling and processing; RSSHub converts supported pages into feeds. Do not add
an independent listing-page crawler for automatic update detection. Acquire
only the body and attachments identifiable as belonging to the detected item.
Do not acquire every historical PDF from a linked listing page. An ambiguous
association is an error rather than permission to broaden acquisition.

## Material and search boundary

Support HTML bodies and PDFs. For HTML, derive text during acquisition and retain
that text, its hash, acquisition time and source references: requested/final URLs,
link anchor text, fragments, headings and short quotes. Discard HTML response bytes;
do not retain or render HTML originals, fetch page assets or execute JavaScript.
Source links are navigation references and may stop resolving after publisher edits.
For PDFs, retain immutable originals in RustFS under ADR 0005. Keep feed signals,
derived HTML text, PDF originals and indexed results distinguishable. Retain earlier
derived text/provenance and PDF originals when processing a feed-visible correction
or replacement, and record their revision relationship. Prefer the current
successfully indexed revision in ordinary search and allow explicit access to earlier revisions. Failed processing must
not erase an earlier usable revision or present incomplete replacement data as
a completed update. Associate revisions only when their material URLs are the
same. Treat a changed material URL as a distinct material rather than inferring
a replacement from its position or the number of attachments. Keep both
materials in ordinary search even if the old URL disappears from the feed.
HTML material identity is URL-based. Compare the complete URL, including its query and fragment,
unless an explicit source-specific rule excludes parts known not to distinguish
materials; never discard these parts universally.

Success means that the corresponding supported material is acquired, yields
non-empty extracted text and is registered in search. It does not certify that
financial values, tables or explanations are sufficient for a particular
analysis. Feed-only title or summary ingestion does not satisfy this boundary.
Keep financial identity assessment separate from acquisition and do not invent
issuer or release identity to make material searchable.

## Error boundary

Use Sentry for acquisition, association, unsupported-format, extraction and
indexing errors, including expected failures returned as values. Keep error
details and handling status in Sentry rather than introducing a database error
inbox. Errors in one item must not stop independent new items. Retain ordinary
discovery, acquisition and provenance records as needed for correct ingestion;
these are distinct from error management.

Failed-material replay, recovery queues and a new retry mechanism are outside
this decision's delivery boundary. Periodic feed polling remains discovery;
it must not silently become a failed-material replay mechanism. Configure Sentry
through private runtime configuration and send only sanitized diagnostics.
Exclude material bodies, attachment bytes, actual target identifiers, source
URLs, credentials and private infrastructure metadata from events, breadcrumbs
and exception context.

## Relationship to other decisions

[ADR 0007](0007-register-pilot-sources-through-an-interface.md) governs target
registration and the separation of acquisition, assessment and operator
decisions. This decision defines the automatic subscription path; the bounded
manual listing collector is not the subscription update detector. Reuse the
existing target registry, source metadata and acquisition safeguards where
applicable. [ADR 0005](0005-store-pdfs-in-rustfs.md) governs retained PDFs, and
[ADR 0010](0010-defer-backups-for-disposable-development-data.md) continues to
govern disposable data and preservation guarantees. Keeping revisions does not
introduce backup or restore guarantees.

[ADR 0014](0014-publish-retained-earnings-through-rss.md) governs output RSS from
retained earnings. Reading that feed continues to read stored results without
starting acquisition or extraction. Input update detection and output feed
eligibility are separate contracts.

Historical backfill, failed-material reprocessing, content-sufficiency analysis,
Excel, XBRL, OCR and subscriptions such as recruitment information are outside
the current earnings boundary. Keep discovery and source material distinct so
later subscription domains do not have to inherit earnings-specific assessment.

<details>
<summary>日本語</summary>

# フィードの更新から決算検索を育てる

運用者が選定した決算情報の購読について、公開元RSSまたはRSSHubフィードで更新を検知する。
フィードは更新の手掛かりと取得元資料への参照を提供するものであり、その内容が分析に十分で
あることを示さない。対応するページ本文とPDF添付を自動取得し、本文を抽出して成功した結果を
検索DBに追加する。公開元がフィードに含める本文量に依存せず、更新を発見できるようにする。
実装範囲は[#232](https://github.com/9renpoto/lens/issues/232)で管理する。

## 更新検知の境界

最初に成功したフィード取得を基準とし、その時点の既存項目は資料取得・検索登録しない。
以後の新着と、フィード上で確認できる変更を処理する。基準と観測した項目の識別・内容を
アプリ再起動後も保持し、通常のポーリングで変更のない資料を繰り返し取得しない。
検知範囲はフィードに現れる情報に制限される。リンク先本文や添付だけの変更は、フィードに
対応する変更が現れない限り検知しない。確認の間に消えた項目の完全な発見は保証しない。

公開元フィードまたはRSSHubルートで対応できる取得先から進める。ポーリングと処理はLens、
対応ページのフィード変換はRSSHubが担う。自動更新検知用に独立した一覧ページ巡回を追加しない。
検知した項目に属すると特定できる本文と添付だけを取得する。リンク先の一覧ページから過去の
PDFをすべて取得しない。対応が曖昧な場合は取得範囲を広げず、エラーにする。

## 資料と検索の境界

HTML本文とPDFに対応する。HTMLは取得時に本文を抽出し、その本文・ハッシュ・取得日時と、
取得前後のURL・リンクのアンカーテキスト・fragment・見出し・短い引用を出典情報として保持する。
HTML応答のバイト列は破棄し、原本保持・レンダリング・ページの付属資源取得・JavaScript実行は
行わない。出典リンクは移動のための参照であり、公開元の編集後には参照できなくなる場合がある。
PDFはADR 0005に従いRustFSに不変の原本を保持する。フィードの更新情報・HTML抽出本文・
PDF原本・検索登録結果を区別する。フィードで検知できた訂正・差し替えを処理した際は、
以前の抽出本文・出典情報・PDF原本を保持し、改訂の関係を記録する。
通常検索では検索登録に成功した現行版を優先し、以前の版も明示的に参照できるようにする。処理失敗によって以前の利用可能な版を消したり、
未完了の差し替えを更新完了として扱ったりしない。資料URLが同じ場合に限り改訂版として
関連付ける。資料URLが変わった場合は、添付の順序や件数から差し替えと推測せず、別資料として
扱い、旧URLがフィードから消えた場合も両方を通常検索に残す。HTML資料はURLで識別する。クエリーとfragmentを含むURL全体を比較し、資料を区別しないと
確認した部分のみを取得先ごとの明示的な規則で除外する。これらの部分を一律に捨てない。

成功とは、対応する対象形式の資料を取得し、空でない本文を抽出して検索登録できたことを指す。
特定の分析に財務数値・表・説明が十分であることは保証しない。フィードの表題・要約だけの
取り込みでは、この境界を満たさない。決算の識別判定は取得と分離し、検索可能にするために
発行元や決算リリースの識別を捏造しない。

## エラーの境界

取得、資料との対応付け、未対応形式、抽出、検索登録のエラーは、戻り値で表す想定済みの失敗も
含めてSentryに記録する。DBにエラー管理一覧を導入せず、詳細と対応状況はSentryで管理する。
ある項目のエラーで独立した他の新着処理を止めない。正しい取り込みに必要な通常の検知・取得・
来歴の記録は保持し、エラー管理とは区別する。

失敗資料の再処理、復旧キュー、新たな再試行機構は今回の提供範囲に含めない。定期的なフィード
確認は更新検知であり、暗黙の失敗資料再処理機構にしない。Sentryは非公開の実行時設定で構成し、
診断情報を匿名化して送信する。資料本文、添付バイト列、実対象の識別子、取得元URL、認証情報、
非公開基盤のメタデータをイベント・breadcrumb・例外コンテキストに含めない。

## 他の判断との関係

[ADR 0007](0007-register-pilot-sources-through-an-interface.md)は対象登録と、取得・判定・
運用者判断の分離を扱う。本判断は自動購読の経路を定義し、上限付き手動一覧収集を購読の更新
検知には使わない。既存の対象台帳・取得先メタデータ・取得時の制約を適用可能な範囲で再利用する。
保存PDFには[ADR 0005](0005-store-pdfs-in-rustfs.md)、破棄可能なデータと保持保証には引き続き
[ADR 0010](0010-defer-backups-for-disposable-development-data.md)を適用する。改訂版の保持は
バックアップや復元の保証を導入するものではない。

[ADR 0014](0014-publish-retained-earnings-through-rss.md)は保存済み決算情報のRSS出力を扱う。
出力フィードの読み取りは引き続き保存結果を読み、取得・抽出を開始しない。
入力の更新検知と、出力フィードの対象条件は別の契約とする。

過去分の遡及取得、失敗資料の再処理、内容の充足判定、Excel・XBRL・OCR、採用情報などの購読は
今回の決算情報の範囲に含めない。将来の購読分野が決算固有の判定を引き継ぐ必要がないよう、
更新の発見と取得元資料を区別する。

</details>
