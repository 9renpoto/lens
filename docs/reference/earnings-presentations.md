# Earnings-presentation PDF assessment

`Lens.Earnings.PresentationAssessment.record(candidate_id)` appends an automated
assessment through [the shared recording contract](earnings-assessments.md),
following [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md).
The candidate is a successful registered-source PDF `HTTPCheck` with a successful
retained acquisition. Target/source metadata and issuer must agree with the
registered target. Source enablement and target activity do not prevent assessment
of retained candidates.

Extract the original first. The assessor uses its latest successful extraction,
even when a newer attempt is pending or failed. No successful extraction returns
`{:error, :extraction_unavailable}`; invalid identifiers or provenance return
`{:error, :invalid_candidate}`. Assessment does not download, extract, adopt a
release or change acquisition facts and operator-confirmed identities.
Reassessment appends history.

## Supported text and outcomes

Version `1` uses NFKC-normalized Japanese text and explicit `コード番号` issuer
evidence from the complete extraction. A supported line states `YYYY年M月期`,
optionally `第1四半期`–`第3四半期`, and `決算説明資料` or `決算説明会資料`.
`第2四半期` may include `(中間期)`; that qualifier on another quarter is
contradictory. Whitespace between components and CRLF are accepted. Without a
quarter the period is `full_year`; the month determines the fiscal year-end.

- `accepted` requires a supported title, a uniquely observed issuer matching the
  registered target, and unambiguous fiscal year-end and period.
- `pending` retains recognizable presentation headings with missing, conflicting
  or unsupported identity. Standalone `決算説明資料`, `決算説明会資料` and
  `決算説明会`, unsupported quarters, title qualifiers and `(訂正)` prefixes do
  not establish complete supported identity. Competing regular-release or
  correction headings also remain pending.
- `excluded` means no recognizable presentation heading. Ordinary releases,
  correction notices and unrelated material are handled separately. Prose
  references, including a title-shaped line followed by a continuation such as
  `をご参照ください`, are not presentation titles.

The URL and registration do not supply missing identity. Unknown or conflicting
fields remain `null`. Optional publication dates use the existing
`Identity.from_text/2` header-date observation. These are limited supported
layouts, not a general slide parser.

Recognized presentations record `document_kind` and `identity.category` as
`earnings_presentation`. The ordinary-release assessor shares presentation
heading detection to keep mixed documents pending. Evidence stores original and
extraction IDs, the SHA-256 of exact extracted text, normalization and up to
16 relevant lines of 256 characters. Decisions use the complete text; the
extraction ID provides full-text traceability.

Run `mix test test/lens/earnings/presentation_assessment_test.exs` for synthetic
fixtures covering presentations, other kinds, ambiguous identity, mixed headings,
provenance, bounded evidence and append-only reassessment. HTML/XBRL collection,
slide interpretation, financial analysis, an operator-review API and scheduling
are outside scope. These tests do not establish live publisher or deployment
verification.

<details>
<summary>日本語</summary>

# 決算説明会PDFの判定

`Lens.Earnings.PresentationAssessment.record(candidate_id)`は
[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md)に従い、
[共通の記録契約](earnings-assessments.md)を通じて自動判定を追記する。
候補は登録取得先の取得成功PDF `HTTPCheck`で、成功した保存済み取得記録を持つ。
対象・取得先メタデータと企業コードは登録対象と一致する必要がある。
取得先の有効設定や対象の活動状態は保存済み候補の判定を妨げない。

先に原本を抽出する。判定器は最新の成功した抽出を使い、それより新しい試行が
処理待ち・失敗でも利用する。抽出成功結果がなければ
`{:error, :extraction_unavailable}`、不正な識別子・来歴には
`{:error, :invalid_candidate}`を返す。資料のダウンロード、抽出、資料の採用、
取得事実や運用者が確定した識別の変更は行わない。再判定は履歴へ追記する。

## 対応する本文と結果

バージョン`1`はNFKC正規化した日本語本文と、抽出全文の明示的な`コード番号`を使う。
対応する行は`YYYY年M月期`、任意の`第1四半期`〜`第3四半期`、
`決算説明資料`または`決算説明会資料`で構成する。`第2四半期`には`(中間期)`を
付記でき、それ以外の四半期への付記は矛盾とする。構成要素間の空白とCRLFを許容する。
四半期がなければ`full_year`とし、決算月から決算期末を求める。

- `accepted`には対応するタイトル、登録対象と一致する一意な企業コード、
  矛盾のない決算期末と期間を必要とする。
- `pending`は認識できる説明資料見出しに識別の不足・矛盾・未対応形式がある場合とする。
  単独の`決算説明資料`・`決算説明会資料`・`決算説明会`、未対応の四半期、
  タイトルへの付記、`(訂正)`接頭辞では完全な対応識別を確立しない。
  通常短信や訂正の見出しが競合する場合も確認待ちに残す。
- `excluded`は認識できる説明資料見出しがない場合とする。通常短信、訂正通知、
  無関係資料は別に扱う。本文中の参照や、タイトル状の行に続いて
  `をご参照ください`などの参照文がある場合は説明資料のタイトルと扱わない。

URLや登録情報から識別の不足を補わない。不明・矛盾する項目は`null`とする。
任意の公開日は既存の`Identity.from_text/2`によるヘッダー日付の観測を使う。
これは限定した対応レイアウトであり、汎用的なスライドパーサーではない。

認識した説明資料の`document_kind`と`identity.category`は`earnings_presentation`とする。
通常短信の判定器も同じ説明資料見出しの検出を使い、混在資料を確認待ちに残す。
根拠には原本・抽出ID、抽出本文そのもののSHA-256、正規化方式、最大16行・
各256文字の関連行を記録する。判定には全文を使い、抽出IDから全文を参照できる。

`mix test test/lens/earnings/presentation_assessment_test.exs`で合成した固定データを検証する。
説明資料、別種類の資料、曖昧な識別、混在する見出し、来歴、根拠の上限、追記型の
再判定を含む。HTML・XBRL収集、スライドの解釈、財務分析、運用者の確認用API、
スケジュール実行は範囲外とする。これらのテストは公開元への実接続や配備の検証を
意味しない。

</details>
