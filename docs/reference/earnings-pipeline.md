# Earnings discovery and identity reference

This describes existing foundation functions, not an integrated collector. `SourceCatalog` reads registered listing sources and current issuer information from `analysis_targets`; sources default to enabled independently of target activity. `HTTPCheck` and HTTP history no longer use the fixed pilot issuer whitelist. `Identity` still uses a fixed fiscal-month map that [task A](../tasks/v0.2.md) must replace with registered configuration. The registration interface follows [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md). Registering or enabling a source does not authorize HTTP acquisition.

## Listing discovery

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
must check source enablement and supply an explicit `allowed_url?` predicate to
`Lens.Earnings.HTTP.fetch/2`. The transport applies that predicate to the initial
URL and every redirect destination before contacting it; without a predicate,
all URLs are rejected. Source registration and enablement are not URL-policy
approval. `SourceCatalog` stores no document host/path policy and provides no
route-authorization predicate. The collector's policy for listing and discovered
document URLs, including external document hosts consistent with
[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md), remains
unimplemented. Policy implementation and collector integration belong to
[#125](https://github.com/9renpoto/lens/issues/125) and
[task E](../tasks/v0.2.md), together with per-company initial candidate filtering,
acquisition state, scheduling, and the manual CLI. The bounded HTTP transport
already exists; it must not be invoked without an explicit acquisition policy.

Tests compare the exact discovered URL sets from all bundled source fixtures and
exercise HTML parsing, relative links, provenance, heading transitions,
duplicate fragments, and input bounds. HTTP tests separately verify rejection
without a policy and rejection of redirect destinations before contact. Reduced
fixtures do not prove compatibility with a publisher's complete live page or
permission to acquire/preserve its PDFs. No new live-source check is claimed.

## Identity and initial selection

`from_text/2` normalizes Unicode compatibility characters, including full-width
digits. It requires an explicit matching `コード番号` and an unambiguous Japanese
`YYYY年M月期 ... 決算短信` title. The current parser checks a configured fiscal month through a fixed implementation map; task A must replace that restriction with registered configuration. The stored
fiscal year-end comes from the PDF title, never a listing-year label or filename.
The result uses the persistence period values `q1`, `q2`, `q3`, and `full_year`.
A title without a quarter denotes full year. An explicit second-quarter
`(中間期)` qualifier and whitespace between extracted date components are supported. Explicit correction notices map to
`correction`; a narrative footnote mentioning corrections does not change the
regular release's category.

An identified result contains `release`, `fields`, `status: :identified`, and
`published_on`. Missing or contradictory identity returns
`status: :pending_confirmation` and `release: nil`, retaining partial fields.
Unsupported issuers return `{:error, :unsupported_issuer}`. Publication dates
must be standalone explicit date lines in the header before the first
`コード番号` field. Dates in financial statements or later narrative are outside
this supported layout and remain unknown. Invalid or competing header date lines leave
`published_on` unknown. Dates embedded in a reference to an earlier release do
not become the correction's publication date. An unknown date does not prevent
otherwise complete identity. No dates are inferred from URLs or acquisition time.
Unrecognized layouts remain pending for operator review; this conservative
parser is not a generic Japanese disclosure classifier.

`select_initial/1` accepts candidates containing the mapping result and the
actual discovered `url`. It selects only identified regular releases, ordered
by fiscal year-end and then period (`q1` < `q2` < `q3` < `full_year`). It returns
`{:ok, candidate}`, `:empty`, or `{:pending_confirmation, candidates}` when the
newest identity has competing candidates. It does not break conflicts by URL or
fall back to an older release. Repeated identical candidate records collapse;
different URLs for one identity require review. A mixed-issuer regular-release
set returns `{:error, :mixed_issuers}`; callers select per company. Pending
candidates and corrections remain available to the caller but are not initial
regular-release choices. Selection does not delete historical identities.


See [HTTP transport](earnings-http.md), [HTTP history](earnings-http-history.md), [run budgets](earnings-run-budget.md), and [historical fixtures](../../test/fixtures/source_catalog/README.md).

<details>
<summary>日本語</summary>

# 決算資料の発見・識別の参照情報

既存の基盤関数の説明であり、一体化した収集処理ではない。`SourceCatalog`は登録済みの一覧取得先と現在の企業情報を`analysis_targets`から読み、取得先は対象のactiveと独立して有効が既定となる。`HTTPCheck`とHTTP履歴は固定の試行対象企業の制限を使わない。`Identity`には固定の決算月マップが残り、[タスクA](../tasks/v0.2.md)で登録設定へ置き換える必要がある。登録インターフェースは[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md)に従う。取得先の登録や有効化はHTTP取得の許可を意味しない。

## 一覧からの発見

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

発見リンクは未確認候補。収集側は取得前に取得先の有効状態を確認し、
`Lens.Earnings.HTTP.fetch/2`へ明示的な`allowed_url?`判定を渡す必要がある。
HTTP取得は初期URLと各リダイレクト先を、その先へ通信する前に判定し、判定が
未指定なら全URLを拒否する。取得先の登録・有効化はURLポリシーの承認ではない。
`SourceCatalog`は資料のホスト・パスポリシーを保持せず、経路の取得許可判定も提供しない。
一覧URLと発見した資料URLに対する収集側のポリシーは、
[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md)に沿う外部資料ホストへの対応を含め、未実装である。
ポリシーの実装と収集への接続は[#125](https://github.com/9renpoto/lens/issues/125)と
[タスクE](../tasks/v0.2.md)で、企業別初期候補選別、取得状態、日次実行、手動CLIとともに扱う。
上限付きHTTP取得は実装済みであり、明示的な取得ポリシーなしに呼び出してはならない。

テストは同梱されたすべての取得元固定データのリンク集合を完全比較し、HTML解析、相対リンク、
出典保持、見出し遷移、フラグメント重複、入力上限を確認する。HTTPテストでは別途、
ポリシー未指定時の拒否と、リダイレクト先への通信前の拒否を確認する。
縮小した固定データだけで発行元の実ページ全体との互換性やPDF取得・保存の許可を
実証したとは扱わない。新しい実サイト確認を行ったとは主張しない。

## 識別と初回選択

`from_text/2`は全角数字などUnicode互換文字を正規化する。企業と一致する
`コード番号`と、一意な日本語の`YYYY年M月期 ... 決算短信`表題を必須とする。
現行パーサーは実装内の固定マップで決算月を確認する。タスクAでこの制限を登録設定へ置き換える。
決算期末はPDF表題から読み、一覧の年度ラベルやファイル名から補わない。
保存期間値は`q1`・`q2`・`q3`・`full_year`。四半期表記のない表題は通期とする。明示的な第2四半期の`(中間期)`表記と、
抽出された日付の各要素間の空白にも対応する。
明示的な訂正通知は`correction`に分類する。本文の注記が訂正に言及するだけでは
通常短信の種類を変更しない。

識別済みの結果は`release`・`fields`・`status: :identified`・`published_on`を含む。
欠落や矛盾がある識別情報は`status: :pending_confirmation`・`release: nil`とし、
部分的な値を保持する。対象外企業は`{:error, :unsupported_issuer}`。
公表日は最初の`コード番号`欄より前のヘッダーにある独立した明示的な日付行から読む。
財務諸表や後続本文の日付は対応レイアウトの範囲外として不明のままにする。
ヘッダーの日付行が不正または複数の異なる値を持つ場合は
不明のままにする。旧短信を参照する文章中の日付は訂正資料の公表日としない。
公表日が不明でも他の識別値が完全なら識別済みにできる。
URLや取得時刻から日付を推測しない。未対応のレイアウトは運用者の確認待ちとし、
汎用の日本語開示分類器とは扱わない。

`select_initial/1`には対応付け結果と実際に発見した`url`を持つ候補を渡す。
識別済みの通常短信だけを、決算期末と期間順（`q1` < `q2` < `q3` < `full_year`）
で選ぶ。戻り値は`{:ok, candidate}`・`:empty`、または最新識別情報に競合候補がある
場合の`{:pending_confirmation, candidates}`。URL順で決着させたり旧期へ戻ったり
しない。同じ候補の繰り返しはまとめるが、同じ識別情報でURLが違えば確認を要求する。
通常短信候補に複数企業が混在する場合は`{:error, :mixed_issuers}`であり、呼び出し側は
企業別に選ぶ。確認待ち候補と訂正資料は呼び出し側で保持するが初回通常短信としては
選ばない。選択によって過去の識別情報を削除しない。


[HTTP取得](earnings-http.md)、[HTTP履歴](earnings-http-history.md)、[実行予算](earnings-run-budget.md)、[過去の固定データ](../../test/fixtures/source_catalog/README.md)も参照する。

</details>
