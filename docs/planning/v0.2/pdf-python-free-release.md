# Python-free release evidence (#94)

Review stack: #96 → #103 (native implementation) → release proof/removal.
The stack remains unmerged. The source keeps Poppler and the existing domain
schema, extractor identity, original bytes, acquisitions and extraction history.

## Measurements

Linux x86_64, OTP 27/Elixir 1.18.3, Poppler 22.12.0 in
`lens-extraction-check`, with `--network none`: five warm-ups followed by 30
interleaved old/new small-PDF runs. Japanese/paragraph and image-only fixtures
and seven boundary cases matched exactly (text, version and failure reason).
The boundary cases include exactly-at-limit, overflow before nonzero exit,
nonzero with small valid text, absent output, blank text, NUL and invalid UTF-8.
Raw samples: [pdf-runner-samples.json](pdf-runner-samples.json).

| Milliseconds | Python median / p95 | Native median / p95 |
| --- | --- | --- |
| End-to-end small PDF | 52.772 / 60.439 | 21.107 / 27.127 |
| Startup to argument rejection | 26.155 / 27.838 | 1.331 / 1.464 |

Startup measures invocation and invalid-argument rejection, not Poppler work.
The small-fixture sample is not a throughput or large-document benchmark. The
contract's material p95 regression threshold is not crossed in this sample.
C source, compiler build and process-control maintenance replace the runtime
Python package; no new runtime package or process library is added.

Same pinned bases and application source after the subreaper correction, Linux
amd64: Python-installed comparison image `ef1cd85413aa` is 184733736 bytes;
Python-free release `3a0cd4e7c07d` is 151146657 bytes, a 33587079-byte reduction.
These are local uncompressed sizes, not registry transfer sizes. The packaged
release helper itself was used for the measurements above; its SHA-256 and
image identity are in the raw sample artifact. It runs as uid/gid 999 (`lens`),
has no Python/reference runner and passed the offline CLI/history check again.

## Persistence and checks

`test/system/earnings_release_check.exs` invokes the actual
`/app/bin/lens-earnings-extract` executable for original, retry and bounded
regeneration in the Python-free release. A disposable PostgreSQL 18.6 database
on the internal `lens-pdf-91-check` network passed: exact original bytes,
acquisition count, successful history after failed regeneration, no pending
handled failures, extractor/version/options and CJK search/rebuild.
The endpoint and collection scheduler remained absent. No publisher access was
available. Do not run this script against a production database.

#103 CI passed compile with warnings as errors, format, dialyzer, coverage and
repository regressions. Its native process and adapter checks include caller
death, outer deadline, protocol violations, invalid text and concurrent runs.
The top PR reruns the checks after removing Python installs and reference tests.
The checked-in PDFs are unchanged. ReportLab regeneration is developer-only.

To reproduce the developer-only comparison, first restore the reference outside
the runtime source tree:

```sh
git show 1466dcd:priv/pdf_runner.py > /tmp/lens-reference-pdf-runner.py
PDF_REFERENCE_RUNNER=/tmp/lens-reference-pdf-runner.py elixir -pa "_build/test/lib/*/ebin" test/system/pdf_runner_comparison.exs
```

Python is needed only for that optional migration comparison. Routine CI and
release extraction use the native helper. Rollback uses the prior compatible
release image; never rewrite originals or history. Per-process/per-file limits,
same-group cleanup and excluded VM/helper SIGKILL, escaped descendants and
kernel uninterruptible sleep are documented in the runtime guide.

<details>
<summary>日本語</summary>

# Pythonなしreleaseの根拠 (#94)

レビュー順は #96 → #103（native実装）→ release検証・削除。未マージのスタック。
Poppler、既存スキーマ、抽出器名、原本、取得、抽出履歴を維持する。

## 測定

通信なしの `lens-extraction-check`、Linux x86_64、OTP 27/Elixir 1.18.3、
Poppler 22.12.0。5回ウォームアップ後、小型PDFを旧・新交互に各30回測定。
日本語・段落、画像のみPDFと7境界ケースで本文・版・失敗理由が完全一致した。
上限ちょうど、非ゼロより超過優先、小さい有効本文付き非ゼロ、本文不在、空白、NUL、
不正UTF-8を含む。生データは [pdf-runner-samples.json](pdf-runner-samples.json)。

| ms | Python 中央値 / p95 | Native 中央値 / p95 |
| --- | --- | --- |
| 小型PDF全体 | 52.772 / 60.439 | 21.107 / 27.127 |
| 起動から不正引数拒否 | 26.155 / 27.838 | 1.331 / 1.464 |

起動測定は引数拒否まででPoppler処理ではない。小型標本であり、大規模・throughputの性能保証ではない。
契約のp95悪化しきい値は超えていない。Cソース、コンパイル、プロセス制御の保守が増えるが、
新しいruntimeパッケージ・ライブラリーは追加しない。

subreaper修正後の同じ固定ベース・アプリソース・Linux amd64で比較。
Python入り `ef1cd85413aa` は184733736 bytes、Pythonなしrelease `3a0cd4e7c07d` は
151146657 bytes。33587079 bytes削減。ローカル非圧縮容量でregistry転送量ではない。
上記測定は実release同梱のヘルパーを使用し、SHA-256とイメージ識別を生データに記録。
uid/gid 999 (`lens`)、Python・旧ランナー不在で、offline CLI/履歴の再検証も成功。

## 保存と検証

`test/system/earnings_release_check.exs` はPythonなしreleaseの実
`/app/bin/lens-earnings-extract` をoriginal・retry・上限付き再生成で呼ぶ。
内部 `lens-pdf-91-check` ネットワークの使い捨てPostgreSQL 18.6で、原本一致、取得件数、
再生成失敗後の成功履歴、処理可能な失敗のpending不在、抽出器・版・options、CJK検索・再構築を確認。
endpoint・収集schedulerは起動せず発行元通信もできない。本番DBでは実行しない。

#103 CIでwarnings-as-errors compile、format、dialyzer、coverage、回帰が成功。
native/adapter検証は呼出元終了、外側期限、不正通信、本文不正、並行実行を含む。
上段PRでPython導入・旧テスト削除後に再実行する。コミット済みPDFは不変、ReportLabは開発用のみ。

任意の比較では旧ランナーをruntimeソース外へ復元する。

```sh
git show 1466dcd:priv/pdf_runner.py > /tmp/lens-reference-pdf-runner.py
PDF_REFERENCE_RUNNER=/tmp/lens-reference-pdf-runner.py elixir -pa "_build/test/lib/*/ebin" test/system/pdf_runner_comparison.exs
```

Pythonはこの任意比較だけに必要で、通常CI・release抽出はnativeを使う。
rollbackは過去の互換releaseへ戻し、原本・履歴を書き換えない。
プロセス・ファイル単位の上限、同一群終了、VM/ヘルパーSIGKILL・別群の子孫・
kernel割込み不能待機の保証外は運用資料に記載する。

</details>
