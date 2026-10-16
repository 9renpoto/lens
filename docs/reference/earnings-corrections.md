# Correction PDF assessment

`Lens.Earnings.Corrections.assess(candidate_id, extraction_id)` assesses a retained
PDF's successful extraction and appends an outcome through
[the shared assessment contract](earnings-assessments.md). The candidate is the
UUID of a successful registered-source PDF `HTTPCheck`; the extraction must
belong to the same acquired original. Invalid candidates return
`{:error, :invalid_candidate}`; absent, pending, failed or mismatched extractions
return `{:error, :invalid_extraction}`. No download, extraction attempt, scheduler
or HTTP endpoint is introduced.

## Supported evidence

Version `1` uses NFKC-normalized Japanese text with explicit `コード番号` issuer
codes and line-delimited headings. It supports `(訂正)` followed by an earnings
release title, a quoted title followed by `の一部訂正に関するお知らせ` or
`の決算数値の訂正に関するお知らせ`, and standalone `一部訂正に関するお知らせ` or
`決算数値の訂正に関するお知らせ`. The reporting title states `YYYY年M月期`, an
optional `第1四半期`–`第3四半期` (`第2四半期` may include `(中間期)`), and `決算短信`, with optional
parenthesized or `〔…〕` qualifiers; spaces before and between qualifiers are
accepted. A title without a quarter denotes
`full_year`. The fiscal month comes from the title; no three-company catalog or
fixed fiscal month is used. This module does not implement the ordinary-release
classifier tracked by #127.

The classifier records issuer, fiscal year-end, period, publication date and
referenced publication date only when uniquely observed. Unknown or conflicting
values remain `null`; evidence retains the observations. Publication dates must
be standalone Japanese dates before the issuer-code line. A supported original
reference is a complete line `YYYY年M月D日に公表した決算短信を訂正します。`
(the final full stop is optional). Other reference wording remains unresolved.
These are explicitly supported layouts, not a general Japanese document parser.

## Outcomes and relationships

- Ordinary releases and unrelated documents are `excluded` from correction
  assessment, with no correction document kind.
- Recognizable but unsupported correction headings, missing/conflicting identity
  or publication evidence, and unresolved relationships are `pending`.
- `accepted` requires a supported correction heading, the registered target's
  explicit issuer, complete reporting identity, and an explicit referenced date
  preceding the correction's own publication date. A matching regular `Release`
  must already exist. Its successful acquisition must predate this candidate,
  and a retained successful extraction must independently substantiate the same
  issuer, reporting identity and referenced publication date, without a
  correction heading. At most 100 matching extraction rows are considered; if
  more exist the relationship stays pending.

A supported link is stored as `identity.corrects_release_id`, with the earlier
extraction ID and referenced date in `evidence.relationship`. The candidate's
extraction ID, normalized headings and identity/date observations are retained
in evidence. Each observation field retains at most eight excerpts of 128
characters, with counts in `observation_counts`; decisions use all observations.
The extraction ID retains the path to the complete text. Missing links stay `null`. This records an assessment relationship;
it does not attach the correction acquisition to the original release, change
acquisition facts, select text, or overwrite an operator's confirmed identity.
Reassessment appends a new record. Numerical correction analysis is outside the
scope of this classifier.

Run `mix test test/lens/earnings/corrections_test.exs` for synthetic retained-text
fixtures covering known, ambiguous, unrelated and ordinary documents, issuer and
period conflicts, publication-reference conflicts, a December full-year title,
unsupported correction markers, extraction provenance and reassessment history.

<details>
<summary>日本語</summary>

# 訂正PDFの判定

`Lens.Earnings.Corrections.assess(candidate_id, extraction_id)`は保存済みPDFの成功した抽出結果を判定し、[共通判定契約](earnings-assessments.md)を通じて結果を追記する。候補は登録取得先の取得成功PDF `HTTPCheck`のUUIDであり、抽出結果は同じ取得原本に属する必要がある。不正な候補は`{:error, :invalid_candidate}`、存在しない・処理待ち・失敗・原本が異なる抽出結果は`{:error, :invalid_extraction}`を返す。ダウンロード、抽出試行、スケジューラー、HTTPエンドポイントは追加しない。

## 対応する根拠

バージョン`1`はNFKC正規化した日本語本文の明示的な`コード番号`と行単位の見出しを使用する。`(訂正)`に続く決算短信タイトル、引用符付きタイトルに続く`の一部訂正に関するお知らせ`または`の決算数値の訂正に関するお知らせ`、単独の`一部訂正に関するお知らせ`または`決算数値の訂正に関するお知らせ`に対応する。対象期間のタイトルは`YYYY年M月期`、任意の`第1四半期`〜`第3四半期`（`第2四半期`では`(中間期)`を付記できる）、`決算短信`で構成し、丸括弧または`〔…〕`による付記を許容する。付記の前や付記間には空白を入れられる。四半期がないタイトルは`full_year`を表す。決算月はタイトルから取得し、固定3社の一覧や固定決算月を使わない。このモジュールは#127の通常短信判定を実装しない。

企業コード・決算期末・対象期間・公開日・参照公開日は、一意に観測できる場合のみ記録する。不明・矛盾する値は`null`とし、根拠には観測内容を保持する。公開日は企業コード行より前にある単独の和文日付を必要とする。元短信の参照は行全体が`YYYY年M月D日に公表した決算短信を訂正します。`である場合に対応する（末尾の句点は省略可能）。ほかの表現による参照は未解決とする。これは明示的に対応するレイアウトの判定であり、汎用的な日本語資料パーサーではない。

## 結果と関連

- 通常短信と無関係資料は訂正判定で`excluded`とし、訂正の資料種類を付けない。
- 認識できるが未対応の訂正見出し、識別情報・公開根拠の不足や矛盾、未解決の関連は`pending`とする。
- `accepted`には対応する訂正見出し、登録対象の明示的な企業コード、完全な対象期間、訂正自体の公開日より前の明示的な参照日を必要とする。一致する通常の`Release`がすでに存在し、その取得成功記録が候補の取得より前でなければならない。保存済みの抽出成功結果によって、訂正見出しなしで同じ企業・対象期間・参照公開日が独立に裏付けられる必要がある。一致する抽出行は最大100件を扱い、それを超える場合は関連を確認待ちに残す。

根拠のある関連は`identity.corrects_release_id`に記録し、元資料の抽出IDと参照日を`evidence.relationship`に保持する。候補の抽出ID、正規化した見出し、識別・日付の観測を根拠に保持する。各観測項目は最大8件・各128文字の抜粋とし、`observation_counts`に件数を残す。判定にはすべての観測を使い、抽出IDから完全な本文を参照できる。関連がない場合は`null`とする。これは判定上の関連の記録であり、訂正の取得記録を元短信に紐付けたり、取得事実を変更したり、本文を選択したり、運用者が確定した識別を上書きしたりしない。再判定は新しい記録を追記する。数値の訂正分析はこの判定の対象外とする。

`mix test test/lens/earnings/corrections_test.exs`で合成した保存済み本文の固定データを検証する。既知の訂正・曖昧な資料・無関係資料・通常短信、企業や対象期間の矛盾、参照公開日の矛盾、12月決算の通期タイトル、未対応の訂正表示、抽出の出典、再判定履歴を含む。

</details>
