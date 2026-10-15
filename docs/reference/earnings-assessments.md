# Earnings assessment records

`Lens.Earnings.Assessments` implements the shared recording boundary in
[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md).
Classifiers supply their conclusions and evidence; this module records them
without classifying PDFs or changing a release's identity.

## Candidate and provenance

A candidate ID is the UUID of a successful PDF `HTTPCheck` from the registered
[candidate collector](earnings-collector.md). The check must reference a
successful acquisition with an original, and its retained `metadata.source_id`
and `metadata.target_id` must match the source's fixed target. Each assessment
stores these IDs and the HTTP check ID. Follow the check's `acquisition_id` to
the acquired original and immutable URL/time facts. Changing the source URL or
disabling collection does not rewrite those facts or assessment history.

There is no second candidate table or pending-identity registry. Historical
downloads without registered-source provenance cannot be assessed through this
contract; the module does not invent or backfill that provenance.

## Recording contract

Call `Assessments.record(candidate_id, attrs)` with atom or string attribute keys:

| Attribute | Contract |
| --- | --- |
| `outcome` | Required: `accepted`, `excluded`, or `pending`. |
| `document_kind` | `earnings_release`, `correction`, or `earnings_presentation`. Required for `accepted`; may be absent for other outcomes. |
| `assessor`, `assessor_version` | Required nonblank identifiers, each at most 100 characters. |
| `reason` | Required nonblank explanation, at most 1000 characters. |
| `identity` | JSON object, default `{}`. Retain unknown values as `null` and conflicting observations explicitly, for example as arrays. |
| `evidence` | Required nonempty JSON object containing supporting observations, such as text excerpts and their location. |

Each JSON object is bounded to 65,536 bytes in both JSON encoding and PostgreSQL
JSONB text representation. JSON keys and values are normalized through JSON
encoding/decoding. Candidate/target/source IDs are derived from retained
provenance; caller attributes cannot override them.

Success returns `{:ok, assessment}`. An inconclusive classifier should record
`pending`; this is a successful recording operation and does not prevent another
candidate from being processed. Invalid attributes return an Ecto changeset;
non-map attributes return `{:error, :invalid_assessment}`. A missing check returns
`{:error, :not_found}`. A malformed ID or ineligible check returns
`{:error, :invalid_candidate}`.

Every successful call appends a distinct assessment, including repeated calls
with identical attributes. Retrying a call does not provide idempotency. The
database rejects updates/deletes, invalid outcomes/kinds, oversized JSON, and
inconsistent candidate provenance. `Assessments.history(candidate_id, limit \\ 100)`
returns the newest records first, ordered by insertion timestamp then UUID, with
a limit of 1–100. A malformed candidate ID returns an empty history; an invalid
limit returns `{:error, :invalid_limit}`.

Recording `accepted` does not confirm missing release identity, attach an
acquisition to a release, or override an operator decision. Existing
`Earnings.confirm_identity/2` associations survive later assessments. Classifier
implementations remain #127–#129; the separate operator-decision records and
inspection/adoption/exclusion API remain #130. No public HTTP endpoint or new
scheduler is introduced by this recording contract.

Run `mix ecto.migrate` before using the module. Migration `20261015000000` adds
the assessment table and its constraints/triggers without rewriting existing
originals, acquisitions, HTTP checks, sources or releases. Automated checks in
`test/lens/earnings/assessments_test.exs` cover all outcomes, provenance rejection,
unknown/conflicting fields, continuing past pending candidates, reassessment
after source changes and identity confirmation, and database immutability.

<details>
<summary>日本語</summary>

# 決算資料の判定記録

`Lens.Earnings.Assessments`は[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md)の共通記録の境界を実装する。判定処理が結論と根拠を渡し、このモジュールがPDFの分類や短信識別の変更を行わず記録する。

## 候補と出典

候補IDは、登録型の[候補収集](earnings-collector.md)が記録した取得成功PDFの`HTTPCheck`のUUIDである。確認記録は原本のある取得成功記録を参照し、保持した`metadata.source_id`と`metadata.target_id`が取得先の固定対象と一致しなければならない。各判定はこれらのIDとHTTP確認IDを保存する。確認記録の`acquisition_id`から取得原本と不変のURL・日時の事実を追跡できる。取得先URLの変更や収集停止は、その事実や判定履歴を書き換えない。

別の候補テーブルや識別確認待ち台帳は作らない。登録取得先の出典がない過去の取得記録は、この契約では判定できない。出典の捏造や自動補完は行わない。

## 記録契約

アトムまたは文字列の属性キーで`Assessments.record(candidate_id, attrs)`を呼び出す。

| 属性 | 契約 |
| --- | --- |
| `outcome` | 必須。`accepted`・`excluded`・`pending`。 |
| `document_kind` | `earnings_release`・`correction`・`earnings_presentation`。`accepted`では必須、その他では省略できる。 |
| `assessor`・`assessor_version` | 必須の空白でない識別子。それぞれ100文字以内。 |
| `reason` | 必須の空白でない説明。1000文字以内。 |
| `identity` | JSONオブジェクト。既定値は`{}`。不明値を`null`、矛盾する観測は配列などで明示して保持する。 |
| `evidence` | 必須の空でないJSONオブジェクト。本文の抜粋と位置など、判定を支える観測を含む。 |

各JSONオブジェクトは、JSONエンコードとPostgreSQLのJSONBテキスト表現の両方で65,536バイト以内とする。JSONのキーと値はエンコード・デコードで正規化する。候補・対象・取得先IDは保持した出典から導出し、呼び出し側の属性では上書きできない。

成功時は`{:ok, assessment}`を返す。判断できない判定処理は`pending`を記録する。これは記録成功であり、ほかの候補の処理を妨げない。不正な属性はEcto changeset、マップ以外は`{:error, :invalid_assessment}`を返す。存在しない確認記録は`{:error, :not_found}`、不正なIDや対象外の確認記録は`{:error, :invalid_candidate}`を返す。

同じ属性での繰り返しも含め、成功した呼び出しごとに別の判定を追記する。呼び出しの再試行に冪等性はない。DBは更新・削除、不正な結果・資料種類、上限を超えるJSON、矛盾する候補出典を拒否する。`Assessments.history(candidate_id, limit \\ 100)`は挿入日時、UUIDの降順で新しい記録から返し、上限は1〜100件とする。不正な候補IDは空の履歴、不正な上限は`{:error, :invalid_limit}`を返す。

`accepted`の記録は、不足する短信識別の確定、取得記録と短信の関連付け、運用者判断の上書きを行わない。既存の`Earnings.confirm_identity/2`による関連は再判定後も保持する。判定処理の実装は#127〜#129、独立した運用者判断の記録と参照・採用・除外APIは#130に残る。この記録契約では公開HTTPエンドポイントや新しいスケジューラーを追加しない。

利用前に`mix ecto.migrate`を実行する。マイグレーション`20261015000000`は判定テーブルと制約・トリガーを追加し、既存の原本・取得記録・HTTP確認・取得先・短信を書き換えない。`test/lens/earnings/assessments_test.exs`では、全結果、出典の拒否、不明・矛盾する項目、確認待ち候補を越えた処理継続、取得先変更と識別確定後の再判定、DBの不変性を検証する。

</details>
