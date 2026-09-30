# PDF runner compatibility contract for #92

Decision: [ADR 0003](../../adr/0003-bound-pdf-runner-replacement.md).
Baseline: `361e1fe6b192a5a23297c596c0032a79302ad0c0` (merged PR #89).
This document freezes observable behavior for [#93](https://github.com/9renpoto/lens/issues/93)
and the release evidence required by [#94](https://github.com/9renpoto/lens/issues/94).
It does not claim that the proposed replacement has passed these tests.

## Evidence and classification

`test/pdf_runner_test.py`: nine tests passed on Linux x86_64 in the existing
`lens-extraction-check` image with `--network none` and the source tree mounted
read-only. A disposable probe of the unchanged runner confirmed the rows marked
**P** below. **T** means covered by existing tests, **S** means derived from
source but not independently exercised here, and **N** means new hardening with
intentional compatibility impact. These distinctions must stay visible in review.

| Case | Current result / precedence | Replacement contract | Evidence |
| --- | --- | --- | --- |
| Real Japanese/CJK, paragraphs | Poppler `-enc UTF-8 -eol unix -nopgbrk`; exact text and reported version | Same flags and bytes, no normalization or truncation in runner | T |
| Image-only / whitespace-only | `empty_output`; Python `str.strip()` decides blankness | Same; include U+3000, form feed and Unicode whitespace in tests | T,P |
| Malformed/unreadable PDF or nonzero extractor | `unreadable` after overflow check | Same, including nonzero with a valid small output file | T,P |
| Invalid UTF-8 or NUL in successful text | `invalid_text`; UTF-8 strict decode precedes blankness | Same | T,P |
| Zero extractor exit without output file | `extractor_unavailable` via `FileNotFoundError` | Preserve this odd but observable classification unless changed in a separately reviewed contract | P |
| Missing `pdftotext`/Python discovery | `extractor_unavailable` before runner; missing executable path inside runner also maps here | Missing Poppler/helper discovery or Poppler launch maps here; do not run without bounds | S |
| Unlaunchable Python runner / malformed JSON | `process_error` in adapter | Native helper launch failure, malformed/unknown status, invalid metadata and protocol overflow: `process_error` | S,N |
| Version probe nonzero | `extractor_unavailable`, version `unavailable` | Same | P |
| Version probe timeout | `timeout`, version `unavailable` | Same | S |
| Version probe diagnostic overflow | Typically nonzero and `extractor_unavailable`; no text-size check in probe | Preserve `extractor_unavailable`; never leak unbounded diagnostics | S |
| Text exactly at chosen byte limit | Success if valid/nonblank | Same; no truncation | P |
| Text one byte above chosen limit | `output_limit` even if extractor exits nonzero | Same; overflow beats nonzero status and invalid text | T,P |
| Nonzero extraction without overflow | `unreadable`, including CPU/AS/FSIZE-related termination where no oversized text file is present | Same; do not infer `timeout` solely from a resource signal | P,S |
| Wall-clock deadline expires first | `timeout`; version reflects last successful probe, else `unavailable` | Same; kill and reap same-group process before response | T,S |
| Ordinary early parent exit with descendants | Same-group descendants killed after parent exits | Same for probe and extraction, including failure paths | T,S |
| Unsupported OS or unavailable limit mechanism | Python runner emits `unsupported_platform` on non-Linux; adapter can instead emit `extractor_unavailable` first if a binary is absent | Precheck Linux and required controls; when helper is callable, return `unsupported_platform` before Poppler; no unrestricted fallback | T,N |
| Invalid public bounds | `{:error, :invalid_options}`, no attempt; helper has internal `invalid_options` | Preserve public rejection for timeout outside 1–30000 ms or text outside 1–8388608 bytes | T,S |
| Handler/caller death and oversized helper response | No outer guarantee; `System.cmd` capture is unbounded | New bounded protocol and owner-death cleanup as specified below; leave historical attempts untouched | N |

An adapter failure before extraction records a failed attempt when `Processing`
has already allocated one. The extractor tuple is `{:ok, %{text: text,
version: version}}` or `{:error, %{reason: reason, version: version}}`.
`Processing` keeps the original/acquisition history, attempt options and
selection semantics; public CLI/JSON failure codes are unchanged. A BEAM VM
crash can leave an allocated pending attempt today and is outside this runner
refactor. Do not promise otherwise without a separate recovery design.

## Fixed limits and phase ordering

Validate public bounds before allocating an attempt. Defaults: 20,000 ms and
8,388,608 text bytes; allowed 1–30,000 ms and 1–8,388,608 bytes. Probe first,
with wall deadline `min(timeout_ms, 2000)`; extraction receives its own
`timeout_ms` deadline. Each child gets `RLIMIT_CORE=0`, `RLIMIT_AS=536870912`,
`RLIMIT_CPU=max(1, ceil(phase_seconds))` and `RLIMIT_FSIZE=phase_output_limit+1`.
The probe phase output limit is 4096, so FSIZE is 4097; its combined stdout/
stderr log is only read to 2048 bytes and decoded with UTF-8 replacement before
trimming. Extraction uses the caller's text limit and FSIZE limit+1 for *each*
file, including diagnostics. `stdin` is `/dev/null`. The private input/temp
directory remains mode 0700, and no publisher network or shell is used.

Check a text file's size before the extraction exit status. If it exceeds the
limit, return `output_limit`; otherwise nonzero exit gives `unreadable`. On zero
exit, absent output gives `extractor_unavailable`, malformed UTF-8 or NUL gives
`invalid_text`, and Unicode whitespace-only gives `empty_output`. Probe failure
returns before extraction. Keep `unavailable` until the probe succeeds. Failure
handling must not silently retain a prefix as successful text. Per-process
RLIMITs and per-file FSIZE do not cap aggregate descendants; process-group kill
does not contain a child that starts a new session. These exclusions are part of
the operator-facing contract, not a claim of general isolation.

## Selected helper protocol and lifecycle

Use one small C11/POSIX helper per extraction, built for Linux from source in
the existing Debian builder. Elixir starts it with Erlang `open_port` using
`spawn_executable` and an argv list, never a shell. The helper launches Poppler
for each phase, sets limits before `execve`, uses a dedicated process group,
monotonic deadlines, waits for the direct child, kills the process group on
*every* phase exit, then returns. The helper owns all OS child supervision;
BEAM does not infer group cleanup from `Port.close` alone.

Keep bulk text out of the transport: the adapter creates a private directory
and passes fixed input, text and version paths. The helper writes text and
version files and emits one ASCII status record of at most 256 bytes on stdout
after cleanup. A single enumerated status maps to the existing failure codes;
unknown/duplicate/oversized records or helper nonzero exit map to
`process_error`. The adapter checks file size before reading, limits text to
the caller's text-byte limit and rejects inconsistent metadata. The version file
contains at most the first 2048 raw probe-log bytes. Decode that prefix with
UTF-8 replacement, then trim using Python-compatible whitespace semantics.
The decoded UTF-8 value may occupy up to 6144 bytes; do not truncate it again. The status record must never contain PDF text or
diagnostics. The adapter deletes the directory after helper termination.
Version metadata remains the Poppler `-v` output, not a helper version.

New hardening: use an outer monotonic budget of
`min(timeout_ms, 2000) + timeout_ms + 2000` ms from helper start. The extra
2000 ms covers startup/cleanup, not additional Poppler execution. A dedicated
supervision worker owns the Port and monitors the caller; it survives caller
termination long enough to finish cancellation and directory cleanup. On caller
termination, protocol violation or outer expiry, send a fixed cancellation
command on helper stdin while keeping the Port open with `exit_status` enabled.
The helper monitors cancellation concurrently with child waiting, kills its
active group and reaps its direct child before exiting. Do not treat Port
closure, EOF or a Port monitor notification as proof of OS helper termination;
the worker waits for the helper's `exit_status` before deleting files or returning.

Cancellation and exit confirmation must fit within the outer budget; reserve
cleanup time rather than starting another unbounded wait after expiry. #93 must
prove cancellation during both phases, caller death, malformed responses and an
unresponsive helper. If the helper cannot respond, an independent, bounded OS
control path must terminate the active group and helper and confirm termination;
its process identities must be recorded before Poppler executes. Specify and
test that path in #93 before accepting the replacement. Failure to prove it
stops #94; closing the Port alone is not an acceptable fallback. Do not claim
that VM SIGKILL, kernel uninterruptible sleep or a child that escapes its group
is covered. Ordinary phase timeouts retain `timeout`; an outer deadline caused
by a stuck helper maps to `process_error` after confirmed cleanup.

The production release target is Linux amd64, matching the current GitHub
Actions image build. Build and link the helper in the builder stage against
the runtime image's glibc, copy only the binary into the release and verify it
as the unprivileged `lens` user. No runtime compiler, Python or extra process
library is selected. Local macOS development keeps explicit unsupported
behavior when the helper is present; missing helper is `extractor_unavailable`.
Linux arm64 or other platforms require a separate build and Linux contract
test before support is claimed.

## Benefit and release gates

The purpose is to remove Python from the production extraction path and
runtime image. A release is worthwhile only if the actual image runs without
Python, has no added runtime package for the helper, and is smaller than the
same-base Python image while meeting the behavior matrix. #94 measures warm-up
and at least 30 small-PDF runs of old and new runners in the same Linux/Poppler
environment; report median/p95 start and end-to-end time and raw samples.
Performance need not improve, but a material regression (more than 20% *and*
20 ms at p95) requires explicit review before shipping. Record added C source,
build and operational maintenance beside saved package size. Failure of any
limit, cleanup or compatibility gate stops dependency removal and reopens this
decision; Python stays until the contract is proved.

<details>
<summary>日本語</summary>

# #92 PDFランナー互換契約

判断は[ADR 0003](../../adr/0003-bound-pdf-runner-replacement.md)。基準はPR #89を含む
`361e1fe6b192a5a23297c596c0032a79302ad0c0`。
本資料は[#93](https://github.com/9renpoto/lens/issues/93)の動作契約と
[#94](https://github.com/9renpoto/lens/issues/94)のrelease検証条件を定める。
置換が試験済みという意味ではない。

## 根拠と分類

既存 `test/pdf_runner_test.py` の9件は、Linux x86_64の既存
`lens-extraction-check` イメージで `--network none`、ソース読取専用の状態で成功した。
下表の **P** は未変更ランナーの使い捨て実測、**T** は既存テスト、**S** はコードからの
推論で未実測、**N** は互換性への影響を明記した新しい強化。レビューでも区別する。

| ケース | 現行の結果・優先順位 | 置換契約 | 根拠 |
| --- | --- | --- | --- |
| 日本語/CJK・段落 | Poppler `-enc UTF-8 -eol unix -nopgbrk`、本文と版 | 引数・本文バイト列を維持。ランナー内正規化・切捨てなし | T |
| 画像のみ・空白 | `empty_output`。Python `str.strip()` で空白判定 | U+3000、改ページ、Unicode空白を含め同じ | T,P |
| 不正PDF・抽出非ゼロ終了 | 上限超過判定後 `unreadable` | 有効な小さい出力ファイルがあっても同じ | T,P |
| UTF-8不正・NUL | `invalid_text`。空白判定より先にUTF-8を検証 | 同じ | T,P |
| 終了0で本文ファイルなし | `FileNotFoundError` から `extractor_unavailable` | 奇妙でも観測可能な分類として維持。変更は別レビュー | P |
| Poppler/Python未検出 | 起動前に `extractor_unavailable`。ランナー内の実行ファイル不在も同じ | Poppler・ヘルパー未検出、Poppler起動失敗も同じ。無上限で実行しない | S |
| Pythonランナー起動不能・JSON不正 | アダプターで `process_error` | ヘルパー起動失敗・不正/未知状態・不正メタデータ・通信超過も同じ | S,N |
| 版確認の非ゼロ終了 | `extractor_unavailable`、版 `unavailable` | 同じ | P |
| 版確認の時間超過 | `timeout`、版 `unavailable` | 同じ | S |
| 版確認ログ上限超過 | 通常は非ゼロで `extractor_unavailable`。本文サイズ判定なし | 同じ。診断を無制限に扱わない | S |
| 本文上限ちょうど | 有効・非空白なら成功 | 同じ。切捨てなし | P |
| 本文上限+1 | 抽出非ゼロ終了でも `output_limit` | 同じ。非ゼロ・不正本文より優先 | T,P |
| 上限超過のない抽出非ゼロ | `unreadable`。CPU/AS/FSIZE終了も本文超過がなければここ | 同じ。シグナルだけで `timeout` と推測しない | P,S |
| 実時間期限超過 | `timeout`。版は成功したprobeの値、なければ `unavailable` | 同じ。返却前に同一群を終了・回収 | T,S |
| 親が先に正常終了し子孫が残る | 同一群の子孫を終了 | 版確認・抽出、失敗経路も同じ | T,S |
| 非Linux・上限制御が使えない | ランナーは `unsupported_platform`。先にバイナリ未検出ならアダプターは `extractor_unavailable` | Linux・制御機能を事前確認。ヘルパー起動可能時はPopplerより先に `unsupported_platform`、無上限fallbackなし | T,N |
| 公開上限引数が不正 | `{:error, :invalid_options}`、試行なし。ヘルパー内にも同名コード | 抽出1–30000 ms、本文1–8388608 bytes以外は同じ | T,S |
| 呼出元終了・過大応答 | 外側の保証なし。`System.cmd` 収集は無制限 | 下記の有界通信と呼出元終了時の後始末を追加。履歴は書き換えない | N |

抽出試行を割り当てた後の処理可能なランナー失敗は失敗試行として記録する。
抽出器タプルは成功 `{:ok, %{text: text, version: version}}` または失敗
`{:error, %{reason: reason, version: version}}`。Processingは原本・取得・試行オプション・
選択規則を維持し、公開CLI/JSONの失敗コードを変えない。BEAM VM停止後のpending試行は
現行でもあり、このリファクタリングの保証外。回復要件は別設計とする。

## 固定上限と処理順

公開上限は試行作成前に検証する。既定20000 ms、本文8388608 bytes、許容範囲は
1–30000 msと1–8388608 bytes。先に版確認し、実時間期限は
`min(timeout_ms, 2000)`。抽出には独立した `timeout_ms`。各子に
`RLIMIT_CORE=0`、`RLIMIT_AS=536870912`、
`RLIMIT_CPU=max(1, ceil(各処理秒数))`、`RLIMIT_FSIZE=各処理出力上限+1`。
版確認の上限4096なのでFSIZEは4097。統合stdout/stderrログ先頭2048 bytesを
UTF-8置換デコード後にtrimする。抽出時のFSIZEは本文上限+1で診断も*各ファイル*に
適用する。stdinは `/dev/null`。原本・一時ディレクトリは0700、shellと発行元通信なし。

抽出終了状態より先に本文ファイルのサイズを調べ、上限超過は `output_limit`。
超過なしの非ゼロは `unreadable`。終了0で本文なしは `extractor_unavailable`、
UTF-8不正・NULは `invalid_text`、Unicode空白のみは `empty_output`。
版確認失敗時は抽出しない。成功するまで版は `unavailable`。本文先頭を成功として
保存しない。RLIMITはプロセス単位、FSIZEはファイル単位で、子孫総量の上限ではない。
群終了は別セッションへ移動した子孫を隔離しない。一般的な隔離とは表現しない。

## 選定したヘルパーとライフサイクル

既存Debian builderでLinux向けC11/POSIXヘルパーをソースからビルドし、抽出ごとに
1プロセス起動する。ElixirはErlang `open_port` の `spawn_executable` とargvリストを
用い、shellは使わない。ヘルパーは各段階でPopplerを起動し、`execve` 前に上限を設定、
専用プロセス群、単調時計による期限、直接の子のwait、*全段階の終了時*に群終了を
実行してから返却する。OS子プロセスの監督はヘルパーの責務であり、`Port.close` だけで
群終了したとはみなさない。

大量本文は通信に流さない。アダプターが非公開ディレクトリを作り、原本・本文・版の
固定パスを渡す。ヘルパーは本文と版をファイルへ書き、後始末の完了後に256 bytes以内の
ASCII状態レコード1件だけをstdoutへ出す。列挙状態を既存失敗コードへ対応し、未知・重複・
過大レコード、ヘルパー非ゼロ終了は `process_error`。アダプターは読み込み前にサイズを調べ、
本文は呼出元のバイト上限に制限し、不整合を拒否する。版ファイルには版確認ログの
生データ先頭2048 bytesまでを保存する。その先頭部分をUTF-8置換デコードしてから、
Python互換の空白規則でtrimする。デコード後のUTF-8値は最大6144 bytesになり得るため、
再度切り捨てない。
状態レコードにPDF本文・診断を含めず、ヘルパー終了後にディレクトリを削除する。
保存版はヘルパー版ではなくPoppler `-v` の結果。

新しい強化として、ヘルパー起動から
`min(timeout_ms, 2000) + timeout_ms + 2000` msの単調時計による外側期限を設定。
追加2000 msは起動・後始末用でPopplerの実行延長ではない。専用の監督workerが
Portを所有して呼出元を監視し、呼出元終了後も取消とディレクトリ削除を完了するまで存続する。
呼出元終了、通信違反、外側期限では、`exit_status` を有効にしたPortを開いたまま、
ヘルパーstdinへ固定の取消コマンドを送る。ヘルパーは子のwaitと並行して取消を監視し、
実行中の群を終了して直接の子を回収してから終了する。Port閉鎖、EOF、Portの監視通知を
OSヘルパー終了の証拠とせず、workerはヘルパーの `exit_status` を待ってからファイル削除・返却する。

取消と終了確認は外側期限内に収める。期限後に無期限のwaitを始めず、後始末時間を確保する。
#93では両段階の取消、呼出元終了、不正応答、応答しないヘルパーを検証する。
ヘルパーが応答できない場合は、独立した期限付きOS制御経路で実行中の群とヘルパーを
終了し、終了を確認する必要がある。対象のプロセス識別情報はPoppler実行前に記録する。
#93でこの経路を具体化・検証してから置換を受け入れる。実証できなければ#94を停止し、
Port閉鎖だけをfallbackにしない。VM SIGKILL、kernelの割込み不能待機、別群へ移動した
子孫は対象外。通常の処理期限は `timeout`、ヘルパー自身の停止による外側期限は
後始末確認後 `process_error` とする。

本番release対象は現行GitHub Actionsビルドと同じLinux amd64。builderでruntimeの
glibcに合わせてリンクし、バイナリだけをreleaseへコピーし、非特権`lens`ユーザーで
検証する。runtimeコンパイラー・Python・追加プロセスライブラリーは選定しない。
ローカルmacOSはヘルパー存在時に明示的な非対応を維持し、不在時は
`extractor_unavailable`。Linux arm64等は個別のビルドとLinux契約試験後に対応を主張する。

## 効果とreleaseゲート

目的は本番抽出経路とruntimeイメージからPythonを外すこと。実イメージでPythonがなく、
ヘルパー用runtimeパッケージを増やさず、同じベースのPython入りイメージより小さく、
挙動表を満たす場合だけ妥当とする。#94は同じLinux/Popplerでウォームアップ後、
小型PDFを旧・新各30回以上測り、起動・処理の中央値/p95と生データを記録する。
高速化は必須でないが、p95で20%かつ20 msを超える悪化は出荷前の明示レビューが必要。
Cソース・ビルド・運用負担と節約したパッケージ容量も併記する。
上限・終了・互換性が満たせなければ依存削除を止め判断を再検討し、合格までPythonを残す。

</details>
