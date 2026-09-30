# Python-free PDF extraction: validation and handoff

Parent: [#91](https://github.com/9renpoto/lens/issues/91).
Decision: [ADR 0003](../../adr/0003-bound-pdf-runner-replacement.md), accepted. Contract: [PDF runner contract](pdf-runner-contract.md).
Baseline: `361e1fe6b192a5a23297c596c0032a79302ad0c0`, reviewed 2026-09-28.

## Review stack and evidence

#96 review references are corrected at `c041647`. Native implementation is in
[#103](https://github.com/9renpoto/lens/pull/103) (`9d9b60f`); Python removal and
release evidence are in [#104](https://github.com/9renpoto/lens/pull/104).
Read [implementation evidence](pdf-native-implementation.md) and
[release evidence](pdf-python-free-release.md), including raw samples and
limitations. Current code is `priv/pdf_runner.c`,
`lib/lens/earnings/pdf_extractor.ex`, `test/pdf_adapter_check.exs` and
`test/pdf_native_runner_check.sh`; release proof uses
`test/system/earnings_release_check.exs`. The stack is unmerged; issue closure
awaits review and merge.

## Historical #92 handoff snapshot (2026-09-28)

The remaining original plan below records the state before #93/#94 implementation
and measurement. Its future/blocked statuses, retain-Python instructions and
Python file paths are historical, not current checkout instructions. Use the
review stack and current files above for further work.

## Execution decision

Gate #92 selected a C11/POSIX Linux helper via an Erlang Port. Python removal
has plausible dependency benefits but no measured benefit yet. #93 implements
and proves the selected design; #94 measures and checks the actual release.
No domain defect requiring a schema or lifecycle change was identified. The gaps
are process supervision and overbroad safety claims; see the ADR. Do not block
#71, #73 or #74 on this refactor. No implementation or benchmark was run in this review.

## Sub-issues and entry conditions

| Order | GitHub sub-issue | Entry / deliverable |
| --- | --- | --- |
| 1 | [#92: contract and selection](https://github.com/9renpoto/lens/issues/92) | Completed: behavior matrix, alternatives and accepted ADR. |
| 2 | [#93: bounded replacement](https://github.com/9renpoto/lens/issues/93) | Blocked by #92. Failing tests first, implement selected helper/adapter, prove bounds in Linux. |
| 3 | [#94: release proof and removal](https://github.com/9renpoto/lens/issues/94) | Blocked by #93. Differential measurement, Python-free CI/release, offline persistence checks and docs. |

These are GitHub parent/sub-issue relationships, with native blocked-by links
#93 → #92 and #94 → #93. Each issue contains scope, relevant files, acceptance
checks, dependencies and stop conditions for a new model to start independently.

## Contract to validate

| Area | Baseline / required decision |
| --- | --- |
| Interface | Keep PDFExtractor success/error tuples, module identity, Poppler version and public CLI/JSON; internal `:python` injection can be replaced. |
| Text | Same Poppler flags, exact valid UTF-8/CJK/paragraphs, no NUL, Unicode-blank rejection, no successful truncation. |
| Timing | Extraction default 20000 ms, allowed 1–30000; version probe min(extraction timeout, 2 s). Define outer helper deadline separately. |
| Resource limits | RLIMIT_AS 512 MiB, CORE 0, CPU max(1, ceil(phase seconds)); per-process, not aggregate. |
| File limits | Text 1–8388608 bytes, default 8388608; extraction FSIZE limit+1 including each diagnostic file; probe FSIZE 4097, version first 2048 bytes. |
| Failure | Preserve timeout, output_limit, invalid_text, empty_output, unreadable, extractor_unavailable, process_error, unsupported_platform. Classify edge-case precedence before changing it. Public invalid_options creates no attempt. |
| Cleanup | Same-group children terminated after normal exit and timeout; probe too. Define helper/caller death policy; do not imply escaped-session containment. |
| Transport | Select framing, response-size ceiling and malformed-response policy; raw text size does not bound JSON bytes. |
| Persistence | No acquisition, original/history rewrite, selection/retry/search change or migration. Handled failures must complete attempts. |

The exact test matrix and selected helper protocol are in the [contract](pdf-runner-contract.md). #93 must
exercise real resource failures, descendants and concurrent runs, not only mocks.
#94 compares warm-up plus at least 30 measured small-fixture runs in the same
Linux/Poppler environment, records median/p95 and image/build tradeoffs, then runs
the actual release with no Python and a disposable offline PostgreSQL database.
Keep the current runner until those gates pass. An optional ReportLab generator
may remain developer-only; checked-in PDF fixtures must not require regeneration
in ordinary CI. Stop and revise the ADR if bounds cannot be preserved, benefit is
unconvincing, or a domain change becomes necessary.

## Handoff and document status

Read latest `AGENTS.md` and compare changes after the baseline before starting.
Main references: `priv/pdf_runner.py`, `lib/lens/earnings/pdf_extractor.ex`,
`processing.ex`, `extractions.ex`, `test/pdf_runner_test.py`, processing tests,
`test/system/earnings_offline_check.exs`, `Dockerfile`, CI and
`docs/earnings-extraction.md`. The current runtime documentation remains accurate
until replacement ships; #94 owns that update. This plan, ADR and contract are included in the #92 documentation change.
Use their latest committed revision when starting #93.

<details>
<summary>日本語</summary>

# Python不要のPDF抽出：検証と引継ぎ

親は[#91](https://github.com/9renpoto/lens/issues/91)、判断は採用状態の
[ADR 0003](../../adr/0003-bound-pdf-runner-replacement.md)。2026-09-28に
`361e1fe6b192a5a23297c596c0032a79302ad0c0` を確認した。

## レビュー用スタックと根拠

#96の参照修正は `c041647`。native実装は
[#103](https://github.com/9renpoto/lens/pull/103) (`9d9b60f`)、Python削除・release根拠は
[#104](https://github.com/9renpoto/lens/pull/104)。
[実装根拠](pdf-native-implementation.md)と[release根拠](pdf-python-free-release.md)の
生データ・限界も参照する。現行コードは `priv/pdf_runner.c`、
`lib/lens/earnings/pdf_extractor.ex`、`test/pdf_adapter_check.exs`、
`test/pdf_native_runner_check.sh`。release根拠は `test/system/earnings_release_check.exs`。
未マージで、Issue終了はレビュー・マージ後に判断する。

## 過去の#92引継ぎ記録 (2026-09-28)

以下の当初計画は#93/#94の実装・測定前の状態を記録する。
将来・blocked状態、Python維持の指示、Pythonファイル参照は過去時点の情報であり、
現在のcheckoutへの指示ではない。後続作業は上記スタックと現行ファイルを使う。

## 実行判断

第1ゲートの#92でErlang Portから呼ぶLinux用C11/POSIXヘルパーを選定した。
#93で実装・実証し、#94で測定と実releaseを確認する。依存削減の効果は未計測。スキーマ・ライフサイクル変更を要する
ドメイン欠陥は見つかっていない。不足はプロセス監督と過大な安全保証の表現で、
ADRに記録した。#71・#73・#74を止めない。今回は実装・性能測定を行っていない。

## サブIssueと着手条件

| 順 | サブIssue | 条件・成果 |
| --- | --- | --- |
| 1 | [#92 契約と方式選定](https://github.com/9renpoto/lens/issues/92) | 完了。挙動表・方式比較・ADR採用。 |
| 2 | [#93 上限付き置換](https://github.com/9renpoto/lens/issues/93) | #92待ち。失敗テストから実装しLinuxで上限を実証。 |
| 3 | [#94 release検証と依存削除](https://github.com/9renpoto/lens/issues/94) | #93待ち。比較測定・PythonなしCI/release・offline保存検証・資料更新。 |

GitHubの正式な親子関係とblocked-by（#93 → #92、#94 → #93）を設定する。
各Issueに範囲・対象ファイル・完了条件・依存・停止条件があり、別モデルが着手できる。

## 検証する契約

| 項目 | 現行・必要な決定 |
| --- | --- |
| 境界 | PDFExtractorの成功・失敗タプル、名前、Poppler版、公開CLI/JSONを維持。内部 `:python` 注入は置換可能。 |
| 本文 | Poppler引数、UTF-8/CJK/段落を維持。NUL・Unicode空白を拒否し成功本文を切り捨てない。 |
| 時間 | 抽出既定20000 ms、1–30000。版確認min(抽出期限,2秒)。外側期限は別定義。 |
| 資源 | RLIMIT_AS 512 MiB、CORE 0、CPU max(1,ceil(各処理秒数))。総量でなくプロセス単位。 |
| ファイル | 本文1–8388608 bytes、既定8388608。抽出FSIZEは上限+1で診断も各ファイル。版確認4097、版文字列先頭2048 bytes。 |
| 失敗 | timeout/output_limit/invalid_text/empty_output/unreadable/extractor_unavailable/process_error/unsupported_platformを維持。端点の優先順位を先に定義。公開invalid_optionsは試行を作らない。 |
| 終了 | 通常終了と期限超過で同一群の子孫を終了。版確認も対象。ヘルパー・呼出元終了方針を定義し別セッション隔離を主張しない。 |
| 通信 | フレーミング・応答上限・不正応答方針を決める。本文上限はJSON上限ではない。 |
| 永続化 | 取得・原本・履歴・選択・再試行・検索・スキーマを変えない。処理可能な失敗は試行を完了させる。 |

詳細な試験表と選定した通信方式は[互換契約](pdf-runner-contract.md)に記載。#93はmockだけでなく実資源制限・子孫・並行処理を検証。
#94は同じLinux/Popplerでウォームアップ後30回以上測定し、中央値/p95・容量・ビルド負担を
記録して、Pythonなしの実releaseと使い捨てoffline PostgreSQLで検証する。
合格までは現行を残す。ReportLab生成器は任意開発用として残せるが、通常CIでPDF再生成を
要求しない。上限を維持できない、効果が不十分、ドメイン変更が必要な場合は停止してADRを見直す。

## 引継ぎと資料の状態

最新 `AGENTS.md` と基準以降の差分を確認してから着手。主な参照は
`priv/pdf_runner.py`、`lib/lens/earnings/pdf_extractor.ex`、
`processing.ex`、`extractions.ex`、`test/pdf_runner_test.py`、processing tests、
`test/system/earnings_offline_check.exs`、`Dockerfile`、CI、
`docs/earnings-extraction.md`。
現行運用資料は置換リリースまで正しく、#94で更新する。本計画・ADR・互換契約は#92の資料変更に含める。#93着手時は最新のコミットを参照する。

</details>
