# Pilot source catalog and PDF link discovery

`Lens.Earnings.SourceCatalog` contains the fixed companies and official listing
routes recorded in the [evaluation ledger](earnings-source-evaluation.md).
Every source has `enabled: false` and
`disabled_reason: :acquisition_conditions_unresolved`. The catalog does not
request material or establish publisher authorization. Source activation,
reviewed polling cadence, and persistence conditions must be resolved before
collection runs against publishers. Unsupported issuers return an explicit
error. This fixed configuration is independent of historical analysis targets.

`Lens.Earnings.Discovery.links/2` parses listing HTML with Floki and resolves
actual PDF anchor hrefs against the final response URL supplied by the caller.
It does not generate filenames, run scripts, read anchor-looking strings inside
scripts/comments, or honor an unreviewed HTML `<base>` override. Relative and
protocol-relative links are resolved; absolute published URLs retain their
spelling. HTML entities are decoded by the parser. Links must use HTTP(S), have
no embedded credentials, and have a `.pdf` path (case insensitive). A filename
in a query parameter alone is insufficient. Discovery preserves links for old
periods, changed URLs, and corrections rather than silently excluding them.
It does not infer identity from a filename or decide which documents to fetch.

Each output includes `href` (the decoded attribute), `url` (resolved original
URL), `comparison_url`, `listing_url`, `anchor_text`, and preceding `headings`
as `{level, text}` pairs. A new heading clears older headings at that level and
below it. These are observed context, not confirmed release identity. Comparison
normalizes scheme/host, default ports, and fragments, retaining the path/query.
Repeated comparison URLs collapse to their first observed provenance record.
The caller must retain the complete listing response metadata separately.

Inputs are capped at 2 MiB (2,097,152 bytes). More than 200 distinct PDF links
returns `{:error, :too_many_links}` rather than a silently truncated result.
Other explicit errors are `:listing_too_large`, `:invalid_html`, and
`:invalid_listing_url`. These discovery limits are independent of the 20 MiB
per-original acquisition limit. This function does no network access or storage.

Discovered links are untrusted candidates. Before any acquisition, the collector
must check source activation and `SourceCatalog.document_url_allowed?/2` for the
initial URL and every redirect target. That predicate allows only the catalog's
HTTPS host on port 443 and reviewed PDF path prefix, without credentials or
decoded dot-segment traversal. It does not authorize fetching a disabled route.
New hosts/paths require source review. The bounded HTTP transport, per-company
initial candidate filtering, acquisition state, schedule, and manual CLI remain
subsequent work for [#71](https://github.com/9renpoto/lens/issues/71).

Tests compare the exact discovered URL sets from all bundled source fixtures and
exercise HTML parsing, relative links, provenance, heading transitions,
duplicate fragments, input bounds, and reviewed route boundaries. Reduced
fixtures do not prove compatibility with a publisher's complete live page or
permission to acquire/preserve its PDFs. No new live-source check is claimed.

<details>
<summary>日本語</summary>

# パイロット取得元台帳とPDFリンク発見

`Lens.Earnings.SourceCatalog`は[評価台帳](earnings-source-evaluation.md)の固定企業と
公式一覧経路を保持する。全社が`enabled: false`・
`disabled_reason: :acquisition_conditions_unresolved`。台帳は取得処理や発行元の許諾を
提供しない。実サイトでの収集前に有効化、巡回間隔、保存条件を解決する必要がある。
対象外企業は明示的なエラーを返す。この固定設定は過去の分析対象モデルと独立する。

`Lens.Earnings.Discovery.links/2`はFlokiで一覧HTMLを解析し、実際のPDFアンカーhrefを
呼び出し側が渡した最終応答URLから解決する。ファイル名の生成、スクリプト実行、
スクリプトやコメント内のアンカー風文字列の解析、未検証のHTML `<base>`指定への追従は
行わない。相対・プロトコル相対リンクは解決し、絶対URLの元の表記を保持する。
HTML実体参照はパーサーで復号する。リンクはHTTP(S)、認証情報なし、パスが`.pdf`
（大文字小文字を問わない）であることが必要。クエリー内のファイル名だけでは対象に
しない。過去期・変更URL・訂正資料のリンクも保持し、黙って除外しない。
ファイル名から識別情報を推測したり取得する資料を選択したりはしない。

結果には`href`（復号した属性）、`url`（解決した元URL）、`comparison_url`、
`listing_url`、`anchor_text`、直前の`headings`（`{level, text}`の組）を含む。
新しい見出しで同じ階層以下の古い見出しを消す。これらは観察した文脈であり、確定した
短信識別情報ではない。比較用にはスキーム・ホスト・既定ポート・フラグメントを
正規化し、パスとクエリーを維持する。同じ比較URLは最初の出典情報にまとめる。
一覧応答の完全なメタデータは呼び出し側が別途保持する。

入力上限は2 MiB（2,097,152バイト）。異なるPDFリンクが200件を超えた場合は
黙って切り詰めず`{:error, :too_many_links}`を返す。他の明示的なエラーは
`:listing_too_large`・`:invalid_html`・`:invalid_listing_url`。
この発見上限は原本取得の20 MiB上限とは別。この関数は通信や保存を行わない。

発見リンクは未確認候補。収集側は取得前に経路の有効状態を確認し、初期URLと全ての
リダイレクト先で`SourceCatalog.document_url_allowed?/2`を確認する必要がある。
この判定は台帳のHTTPSホスト・443ポート・検証済みPDFパス接頭辞だけを許容し、
認証情報や復号後のドット区間による経路逸脱を拒否する。無効経路の取得許可ではない。
新しいホスト・パスは取得元レビューが必要。上限付きHTTP取得、企業別初期候補選別、
取得状態、日次実行、手動CLIは[#71](https://github.com/9renpoto/lens/issues/71)の後続作業。

テストは同梱されたすべての取得元固定データのリンク集合を完全比較し、HTML解析、相対リンク、
出典保持、見出し遷移、フラグメント重複、入力上限、検証済み経路境界を確認する。
縮小した固定データだけで発行元の実ページ全体との互換性やPDF取得・保存の許可を
実証したとは扱わない。新しい実サイト確認を行ったとは主張しない。

</details>
