# Earnings identity reference

Identity assessment is independent of acquisition. See the [subscription guide](earnings-subscriptions.md) for feed updates and material acquisition.

## Identity assessment

`from_text/2` normalizes Unicode compatibility characters, including full-width
digits. It requires an explicit matching `コード番号` and an unambiguous Japanese
`YYYY年M月期 ... 決算短信` title. The parser reads the fiscal month from the title and validates the date without a fixed issuer map. The stored
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

See [HTTP transport](earnings-http.md), [HTTP history](earnings-http-history.md), and [fictional fixtures](../../test/fixtures/source_catalog/README.md).

<details>
<summary>日本語</summary>

# 決算資料の識別の参照情報

識別判定は取得と独立している。フィードの更新と資料取得は[購読手順](earnings-subscriptions.md)を参照する。

## 識別の判定

`from_text/2`は全角数字などUnicode互換文字を正規化する。企業と一致する
`コード番号`と、一意な日本語の`YYYY年M月期 ... 決算短信`表題を必須とする。
パーサーはタイトルから決算月を読み取り、固定の企業別マップを使わず日付を検証する。
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

[HTTP取得](earnings-http.md)、[HTTP履歴](earnings-http-history.md)、[架空の固定データ](../../test/fixtures/source_catalog/README.md)も参照する。

</details>
