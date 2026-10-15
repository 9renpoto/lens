# Assess retained earnings releases

`Lens.Earnings.ReleaseAssessment.record(candidate_id)` appends an automated
assessment through `Assessments.record/2`. `candidate_id` is a successful PDF
HTTP check from a registered source, with a successful retained acquisition.
The source and target metadata and issuer must agree. Source enablement and
target activity do not prevent assessment of previously collected candidates.

Extract the retained original first through `Processing.extract/2`. Assessment
uses the latest successful extraction of that original; it never fetches a URL
or runs extraction itself. Missing extraction returns
`{:error, :extraction_unavailable}`; invalid candidate provenance returns
`{:error, :invalid_candidate}`. Repeating assessment appends another record.

An explicit supported Japanese earnings-release heading, matching issuer code,
and unambiguous reporting year-end and period produce `accepted`. The issuer
need not belong to the former three-company pilot. `Identity.from_text/2` now
reads the fiscal month from the document instead of checking a fixed issuer
calendar. Callers that relied on rejection of other issuers or changed year-ends
must use the registered candidate boundary or apply their own policy.

Missing or contradictory release identity and competing document-kind headings
produce `pending`. Unrelated documents, presentations without a supported release
heading, and recognized corrections produce `excluded` for this assessor.
Correction relationships and presentation assessment belong to separate assessors.
Unknown or contradictory publication dates remain `nil`. No financial numbers
are analyzed, and assessment does not adopt a release or change acquisition facts.

Evidence includes the retained original ID, extraction ID, SHA-256 of the exact
extracted text, NFKC normalization, and up to 16 relevant lines of 256 characters
each. Complete extraction text remains available through that extraction record;
truncated observations are not the classifier input. Fixtures under
`test/fixtures/earnings/assessment` are synthetic extraction text, including a
non-pilot December year-end, unrelated documents and contradictory evidence.
These tests establish deterministic assessment behavior, not live publisher or
physical deployment verification.

<details>
<summary>日本語</summary>

# 保存済み決算短信の判定

`Lens.Earnings.ReleaseAssessment.record(candidate_id)` は
`Assessments.record/2` を通じて自動判定を追記する。`candidate_id` は登録取得先の
成功したPDF HTTPチェックであり、成功した保存済み取得記録を持つ。
取得先・対象メタデータと企業コードの整合性が必要となる。取得先の有効設定や
対象の活動状態は、取得済み候補の判定を妨げない。

先に `Processing.extract/2` で保存済み原本を抽出する。判定には、その原本の
最新の成功した抽出を使い、URL取得や抽出処理自体は実行しない。抽出がない場合は
`{:error, :extraction_unavailable}`、候補の来歴が不正な場合は
`{:error, :invalid_candidate}` を返す。再判定は別の記録を追記する。

対応する日本語の決算短信見出し、合致する企業コード、矛盾のない決算期末と期間が
明記されていれば `accepted` とする。旧固定3社に含まれない企業も対象となる。
`Identity.from_text/2` は固定の企業別決算月ではなく資料の決算月を読む。
他企業や決算期末変更の拒否に依存した呼び出し元は、登録候補の境界を利用するか、
独自の方針を適用する必要がある。

識別情報の不足・矛盾や資料種類の競合見出しは `pending` とする。無関係資料、
対応する短信見出しがない説明資料、認識できた訂正資料は、この判定器では
`excluded` とする。訂正関係と説明資料の判定は別の判定器の責務となる。
不明または矛盾する公開日は `nil` を維持する。財務数値の分析、決算資料の採用、
取得事実の変更は行わない。

根拠には原本ID、抽出ID、抽出テキスト全体のSHA-256、NFKC正規化、最大16行・
各256文字の関連行を記録する。全文は抽出記録に残り、判定入力には切り詰め前の
全文を使う。`test/fixtures/earnings/assessment` は、固定外企業の12月決算期、
無関係資料、矛盾する根拠を含む合成抽出テキストである。テストが検証するのは
決定的な判定挙動であり、公開元への実接続や実環境の配備は検証していない。

</details>
