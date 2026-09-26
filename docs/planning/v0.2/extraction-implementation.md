# Retained-original extraction implementation

Issue: [#72](https://github.com/9renpoto/lens/issues/72). Base: #87,
merged as `45ad24c`. This is an implementation proposal, not a completed feature.

Current status: PR #90 is draft and implementation is stopped for
[search-size design review](extraction-search-size-design.md). A generated-vector
size failure can abort valid extraction storage; the green checks do not resolve
this design problem.

## Foundation implementation status

The first slice implements `Lens.Earnings.Extractions.begin/3`, `succeed/2`,
`fail/2`, `latest_success/1` and `release_text/1`. Attempts use the table's
PostgreSQL sequence ID as their deterministic allocation order. Finishing uses
an atomic conditional update of pending attempts. Release selection executes in
one SQL statement, so newest-original status and selected text share a snapshot.
An existing release with no eligible originals or no successful text returns
an inspectable result with `extraction: nil`. An absent release returns
`{:error, :not_found}`. `stale` describes original-version lag; a failed retry
of the same original is visible through `latest_attempt`.

Validation: `mix test --warnings-as-errors --seed 0` passed with 148 tests.
PDF extraction, CLI, search integration and extractor options remain subsequent
slices; this foundation does not claim the full issue is complete.

## PDF process prototype

The second slice is on `codex/earnings-pdf-processing`, stacked on PR #88.
`priv/pdf_runner.py` invokes local Poppler `pdftotext` without a shell, preserves
reading-order text and paragraph breaks, and records the executable's version.
The proposed fixed ceiling is 30 seconds per extraction, 512 MiB address space,
8 MiB text output, no core dump, bounded diagnostic files and a CPU-time limit.
The version probe has a separate two-second ceiling. Timeout and normal exit
both clean up the process group so descendants do not remain running.

This runner requires Linux, matching the production container; unsupported
platforms fail explicitly rather than silently dropping the memory bound.
Eight black-box process tests passed in Linux with publisher network access disabled,
including Japanese text/paragraph extraction and an actual image-only PDF.
Synthetic ReportLab fixtures were rendered and visually inspected. Japanese CID
fonts require `poppler-data`; runtime and CI install it alongside `poppler-utils`
and Python. `Lens.Earnings.Processing.extract/2` reads retained PostgreSQL bytes,
records success or failure and supports another attempt without acquisitions.
The Elixir suite passed with 153 tests, including process-start failure and
invalid resource bounds. The bounded CLI and Linux end-to-end PostgreSQL
extraction check also passed in an internal Docker network. It verified
original bytes and acquisition counts, retry, a one-original regeneration limit
and absence of the scheduler and endpoint. See [operations](../../earnings-extraction.md).
An image-only PDF reports `empty_output`;
the runner does not claim to distinguish it from other textless PDFs.

Reference: [Poppler pdftotext manual](https://manpages.debian.org/bookworm/poppler-utils/pdftotext.1.en.html).

## Search slice status

The third slice is on `codex/earnings-search`. Extraction attempts have derived
`search_text` and indexed full-text vectors; successful completion and rebuilding
share `Lens.Search.Normalizer`. Ordinary search selects one successful extraction
per release before matching, then combines it with feeds before pagination.
It exposes original/attempt IDs and stale status. A minimal release detail API
provides exact plain text and pending/failed state even without a search result.

Validation: 159 Elixir tests and eight PDF process tests passed on Linux.
Fresh-database migration, real retained PDF extraction, search and rebuild also
passed with publisher access disabled in an internal Docker network.
The exact production Dockerfile built successfully for the second slice;
`poppler-data 0.4.12-1` was verified available in `bookworm/main`, contradicting
the review's proposed need for `non-free`. The evidence was posted on PR #89.

## Context map

| File | Purpose and planned change |
| --- | --- |
| `lib/lens/earnings.ex` | Retained bytes and confirmed release associations; expose extraction inspection and eligible-original selection. |
| `lib/lens/earnings/original.ex` | Immutable, globally deduplicated bytes; leave unchanged. |
| `lib/lens/earnings/acquisition.ex` | Immutable acquisition provenance; read associations without adding acquisition records. |
| `lib/lens/earnings/release.ex` | Immutable logical identity; store mutable derived data separately. |
| `lib/lens/earnings/extraction.ex` (new) | Extraction attempts, exact original reference, status, text, failure and extractor identity. |
| `lib/lens/earnings/pdf_extractor.ex` (new) | Bounded local PDF process with no publisher requests. |
| `lib/lens/search.ex` | Include one selected earnings result per release and rebuild its derived search fields. |
| `lib/lens/search/normalizer.ex` | Reuse existing normalization for feed and earnings text. |
| `lib/mix/tasks/lens.earnings.extract.ex` (new) | Explicit single-original retry and bounded regeneration. |
| `priv/repo/migrations/` | Add derived tables and constraints without weakening provenance triggers. |
| `Dockerfile` | Install the chosen extractor in the runtime image. |
| `docs/search.md`, `docs/operations.md` | Document extraction, failures, selection and offline rebuilding in both languages. |

| Tests | Required observable coverage |
| --- | --- |
| `test/lens/earnings_test.exs` | Original and acquisition invariants remain intact. |
| New extraction tests and synthetic PDF fixtures | Text and paragraph output; malformed, empty, image-only and timed-out input; retry and regeneration. |
| `test/lens/search_test.exs` | One result per release; deterministic selection, stale text, no text, CJK and feed regression. |
| New CLI tests | Reject unbounded/invalid input; retry one original; process no more than the requested limit. |
| `test/mix/tasks/lens.search.rebuild_test.exs` | Rebuild uses the same normalized canonical extracted text. |

Reference patterns: `Lens.Earnings.record_success/1` transactions,
`Lens.Search.rebuild/1` keyset batches, and `Lens.DataCase` SQL sandbox.
The map was checked against the merged preservation implementation before
implementation. Database migrations, runtime dependencies and additive search
API fields will be needed.

## Proposed invariants

An extraction belongs to an original, not an acquisition or release. The same
original can be associated with multiple releases. Keep attempts so that a failed
regeneration does not destroy a previous successful result. Each attempt records
pending/succeeded/failed status, extractor name and version, options, start and
finish times, failure code and successful plain text. A missing extractor is a
processing failure, never an acquisition failure.

Only successful acquisitions with confirmed `release_id` make an original
eligible. Order distinct originals for a release by their **earliest successful
acquisition time for that release**, then original UUID, both descending. Repeated
acquisition of identical bytes does not promote an old original. Identity
confirmation makes an existing association eligible without changing its ordering.
This is an acquisition-based ordering; it does not infer publisher revision dates.

Select the newest eligible original with a successful extraction. Within one
original, select successful attempts by monotonically allocated attempt sequence,
not completion time. An older attempt finishing late cannot displace a newer
successful attempt. Failed attempts preserve earlier successful text. A result
is stale when its selected original differs from the newest eligible original;
also expose the latest attempt status so failed regeneration remains inspectable.
With no successful extraction, retain an inspectable release with no search row.

Prefer selection from authoritative associations and attempts at query time over
updating an immutable release or an asynchronously maintained selected pointer.
Any materialized normalization must be tied to the successful attempt it describes.
Rebuilding search fields must never invoke acquisition or PDF extraction.

## Reviewable implementation sequence

1. Extraction persistence and deterministic selection, with concurrency and
   preservation regression tests.
2. Real PDF extraction and bounded offline CLI, with synthetic PDF fixtures and
   process timeout/resource tests.
3. Search integration and rebuild, bilingual operations documentation and full
   feed/CJK regression verification.

Use stacked PRs if these boundaries are needed to keep review manageable. Request
review on concrete tested changes. If review identifies a design problem, stop
implementation and revise this proposal before continuing. Exact process resource
limits and extractor choice must be validated before step 2; killing an Elixir
task alone does not establish that its operating-system child has terminated.

<details>
<summary>日本語</summary>

# 保存原本からの本文抽出の実装

対象は [#72](https://github.com/9renpoto/lens/issues/72)、基点は #87 の
マージコミット `45ad24c`。この資料は実装案であり、機能の完成報告ではない。

現在はPR #90をドラフトに戻し、[検索サイズの設計見直し](extraction-search-size-design.md)のため
実装を中断している。生成ベクトルの上限超過で有効な抽出本文の保存が中断し得る。
CI成功ではこの設計問題を解決できない。

## 基盤実装の状態

第1段階は `Lens.Earnings.Extractions.begin/3`、`succeed/2`、`fail/2`、
`latest_success/1`、`release_text/1` を実装する。PostgreSQLの連番IDで
試行の割当順を決定し、待機中の試行だけを原子的に完了させる。
短信の選択は1つのSQL文で実行し、最新原本の状態と選択本文のスナップショットを揃える。
対象原本や成功本文がない既存短信は `extraction: nil` として確認できる。
存在しない短信は `{:error, :not_found}` を返す。`stale` は原本の版の遅れを表し、
同じ原本の再試行失敗は `latest_attempt` で確認する。

検証：`mix test --warnings-as-errors --seed 0` は148件成功。
PDF抽出、CLI、検索連携、抽出器オプションは後続段階であり、issue全体の完成ではない。

## PDFプロセスの試作

第2段階はPR #88に積む `codex/earnings-pdf-processing` ブランチで進める。
`priv/pdf_runner.py` はシェルを使わずローカルのPoppler `pdftotext` を呼び、
読順の本文と段落区切りを保持し、実行ファイルの版を記録する。
上限案は抽出30秒、仮想アドレス空間512 MiB、本文8 MiB、コアダンプ禁止、
診断ファイルとCPU時間の上限。版の確認は別途2秒以内とする。
タイムアウトと通常終了の両方でプロセス群を終了し、子プロセスを残さない。

本番コンテナと同じLinuxを必要とする。非対応環境ではメモリ制限を外さず、明示的に失敗する。
`--network none` のLinuxコンテナで、日本語本文・段落抽出と画像のみPDFを含む
発行元通信を無効にしたLinuxで8件のプロセステストが成功した。
ReportLabの合成固定データは描画して目視確認した。
日本語CIDフォントには `poppler-data` が必要で、本番とCIは `poppler-utils` と
Pythonに加えて導入する。`Lens.Earnings.Processing.extract/2` はPostgreSQLの
保存原本から成功・失敗を記録し、取得を増やさず再試行できる。
プロセス起動失敗と不正上限を含むElixirの153テストが成功した。
内部Dockerネットワークで上限付きCLIとPostgreSQLからの一連の抽出検証も成功し、
原本バイト列・取得件数、再試行、再生成1原本の上限、スケジューラ・endpoint未起動を確認した。
[運用説明](../../earnings-extraction.md)を参照。
画像のみのPDFは `empty_output` とし、他の本文なしPDFと
区別できるとはしない。

参照：[Poppler pdftotextマニュアル](https://manpages.debian.org/bookworm/poppler-utils/pdftotext.1.en.html)。

## 検索段階の状態

第3段階は `codex/earnings-search`。抽出試行に派生 `search_text` と索引付き全文検索ベクトルを追加し、
成功時と再構築で `Lens.Search.Normalizer` を共用する。通常検索は照合前に短信ごとの成功抽出を選び、
フィードと統合してからページングする。原本・試行IDと旧版状態を返す。最小限の短信詳細APIで、
検索結果がなくても正確な本文と待機・失敗を確認できる。

LinuxでElixir159件・PDF処理8件成功。内部Dockerネットワークで発行元通信を無効にし、
空DBマイグレーション、実保存PDFの抽出、検索、再構築も成功した。
第2段階の本番Dockerfile全体もビルド成功。`poppler-data 0.4.12-1` は `bookworm/main` にあり、
レビューの `non-free` 必要という指摘とは異なることを実証し、PR #89に返信した。

## 関連ファイル

`lib/lens/earnings.ex` は原本取得と短信の関連を読み、抽出状況と対象原本の
選択を提供する。`original.ex` の共有・不変原本、`acquisition.ex` の取得履歴、
`release.ex` の不変な短信識別情報は維持する。新しい `extraction.ex` に抽出履歴、
`pdf_extractor.ex` に上限付きPDF処理を置く。`lib/lens/search.ex` と既存の
`normalizer.ex` を使い、短信ごとの検索と再構築を実装する。
新しい `lens.earnings.extract` Mix task は原本1件の再試行と上限付き再生成を提供する。
マイグレーションで派生テーブルと制約を追加し、`Dockerfile` に抽出器を導入する。
`docs/search.md` と `docs/operations.md` を日英で更新する。

テストでは保存の不変条件、合成PDFの本文・段落、破損・空・画像のみ・タイムアウト、
再試行と再生成、短信1件につき検索結果1件、決定的な選択と旧版表示、本文なし、
CJKとフィードの回帰、CLIの入力拒否と件数上限、共通正規化による再構築を検証する。
既存の取得トランザクション、keysetによる再構築、SQL sandboxを参照する。
関連ファイルはマージ済み実装と照合済み。DB変更、実行時依存、検索APIへの追加項目が必要。

## 不変条件の案

抽出は原本に紐付ける。同じ原本が複数の短信で使われる場合もある。
抽出履歴を保持し、再生成の失敗で以前の成功本文を失わないようにする。
各履歴には待機・成功・失敗、抽出器名と版、オプション、開始・完了日時、
失敗コード、成功本文を記録する。抽出器がない場合も取得失敗とは区別する。

識別が確定した取得成功だけを対象にする。短信ごとの原本の順序は、各原本の
その短信に対する最初の取得成功日時、原本UUIDの順で降順とする。
同じバイト列の再取得で旧版を昇格させない。識別の確定も順序を変えない。
これは取得に基づく順序であり、発行元の訂正日時を推測しない。

対象原本のうち抽出成功のある最新版を選ぶ。同じ原本の成功履歴は、完了日時ではなく
単調増加する試行番号で選ぶ。古い処理の遅延完了で新しい成功を上書きしない。
失敗後も以前の成功本文を維持する。選択原本が最新対象原本と異なる場合は旧版と表示し、
最新試行の状態も示す。成功本文がない短信は確認可能にし、検索行は作らない。

不変短信や非同期の選択ポインタを更新するより、取得の関連と抽出履歴から検索時に
選択する方式を優先する。正規化データは対応する成功履歴に紐付ける。
検索の再構築は取得やPDF抽出を呼び出さない。

## レビュー単位

1. 抽出履歴と決定的な選択。競合と原本保存の回帰テストを含む。
2. PDF抽出と上限付きオフラインCLI。合成PDFとプロセス資源・タイムアウト検証を含む。
3. 検索・再構築、日英の運用説明、フィード・CJK回帰検証。

レビューしやすい規模にする必要があればスタックPRに分け、テスト済みの変更をレビュー依頼する。
設計上の指摘があれば実装を中断して本案を見直す。抽出器と資源上限は第2段階の前に検証する。
Elixir taskを終了するだけではOSの子プロセスの終了を保証できない。

</details>
