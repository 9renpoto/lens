# Pilot release identity and initial selection

`Lens.Earnings.Identity` maps extracted PDF identity text for the fixed pilot
issuers 6857, 9983, and 8035. It performs no HTTP requests, PDF extraction, or
persistence. Collection must supply actual extracted text and preserve its
listing, URL, and source metadata separately. These rules are a foundation for
[#71](https://github.com/9renpoto/lens/issues/71); the collector, schedule, and
manual command remain separate work. All source routes remain inactive while
the conditions in the [catalog](earnings-source-evaluation.md) are unresolved.

`from_text/2` normalizes Unicode compatibility characters, including full-width
digits. It requires an explicit matching `コード番号` and an unambiguous Japanese
`YYYY年M月期 ... 決算短信` title. The fiscal month must match the pilot issuer:
March for Advantest and Tokyo Electron, August for Fast Retailing. The stored
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

The focused tests exercise the dated/transcribed [source fixtures](../test/fixtures/source_catalog/README.md),
full-year selection, missing dates, contradictions, correction classification,
issuer isolation, and conflicting URLs. They do not establish live listing
compatibility, PDF extraction quality, or publisher permission.

<details>
<summary>日本語</summary>

# パイロットの短信識別と初回選択

`Lens.Earnings.Identity`は固定3社（6857・9983・8035）のPDF識別文字列を対応付ける。
HTTP取得・PDF抽出・保存は行わない。収集側は実際の抽出文字列を渡し、一覧・URL・
取得元情報を別途保持する。[#71](https://github.com/9renpoto/lens/issues/71)の基盤であり、
収集処理・日次実行・手動コマンドは別の作業。
[台帳](earnings-source-evaluation.md)の条件が未解決の間、全経路は無効のままにする。

`from_text/2`は全角数字などUnicode互換文字を正規化する。企業と一致する
`コード番号`と、一意な日本語の`YYYY年M月期 ... 決算短信`表題を必須とする。
決算月はアドバンテスト・東京エレクトロンが3月、ファーストリテイリングが8月。
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

テストは日付付きで転記した[取得元固定データ](../test/fixtures/source_catalog/README.md)、
通期選択、公表日欠落、矛盾、訂正分類、企業分離、URL競合を検証する。
実一覧の互換性・PDF抽出品質・発行元の許可を実証するものではない。

</details>
