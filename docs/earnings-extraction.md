# Extract retained earnings originals

Apply database migrations before processing. Run these commands in a fresh Mix
process with the usual PostgreSQL configuration. The task starts only Ecto and
the repository, and refuses to run if the collection scheduler is already
running. It does not start the web endpoint or fetch publisher material.

```sh
mix lens.earnings.extract --original ORIGINAL_UUID
mix lens.earnings.extract --retry FAILED_ORIGINAL_UUID
mix lens.earnings.extract --regenerate --limit 10
mix lens.earnings.extract --regenerate --limit 10 --after-original LAST_ORIGINAL_UUID
```

`--original` creates one attempt from retained bytes. `--retry` requires the
original's most recently allocated attempt to have failed. `--regenerate`
processes distinct originals with at least one completed attempt, in ascending
UUID order. Supply a limit between 1 and 100; there is no unbounded mode. Use
the returned `next_after` cursor for the next batch. An empty batch returns a
null cursor. Pending originals without completed attempts are not selected.

Each JSON result identifies its attempt, original, status, failure reason and
extractor version. A processing failure is a recorded `failed` outcome, and
does not make the command fail to execute; inspect the JSON status. Invalid
arguments, missing originals and invalid retry targets raise a CLI error.
Acquisition records and original bytes never change during processing.

## Runtime and bounds

Extraction requires Linux, Python 3, Poppler `pdftotext` and `poppler-data` for
Japanese CID-font mappings. The production image and CI install these packages.
OCR is not performed. Image-only or otherwise textless PDFs report
`empty_output`; malformed or unreadable PDFs report `unreadable`.

The process runs without a shell using `-enc UTF-8 -eol unix -nopgbrk`. Reading
order and paragraph breaks are retained where Poppler can recover them. Limits
are 512 MiB of virtual address space, no core dump, bounded output/diagnostic
files and a CPU limit derived from the timeout. The default timeout is 20 seconds
and the text limit is 8 MiB; use `--timeout-ms` (1–30000) and
`--max-output-bytes` (1–8388608) to lower or adjust them within those ceilings.
Version probing takes at most two additional seconds. Both timeout and ordinary
exit terminate the process group. Unsupported platforms fail explicitly.

Useful failure codes include `timeout`, `output_limit`, `invalid_text`,
`extractor_unavailable`, `process_error` and `unsupported_platform`.
NUL-containing, invalid UTF-8 and blank text are rejected. Successful text is not
truncated to fit an output limit. Earlier successful attempts remain retained
after failed regeneration.

## Inspect and select text

`Lens.Earnings.Extractions.latest_success(original_id)` returns the newest
successful attempt for an original. `release_text(release_id)` returns the
selected extraction, newest eligible original, that original's latest attempt
and a `stale` flag. It uses confirmed successful acquisition associations only.
Distinct originals are ordered by earliest acquisition time for that release,
then UUID, descending. Reacquiring old bytes does not promote them. Successful
attempts for one original are ordered by allocation sequence, not completion.

A newer failed original leaves older successful text selected with `stale: true`.
A release without successful text remains inspectable with `extraction: nil`.
The latest attempt exposes pending, succeeded or failed status independently of
the selected successful text. Search integration is the subsequent slice of #72.

## Verification

Synthetic PDFs and their ReportLab generator live in `test/fixtures/`.
`python3 -m unittest discover -s test -p pdf_runner_test.py` checks real Japanese
text, image-only input, process failures, output limits and descendant cleanup.
`test/system/earnings_offline_check.exs` is a scratch-database check run with
`mix run --no-start`. It migrates an empty test database and verifies the real
CLI, bytes and acquisition counts. Run it in an internal Docker network with
only PostgreSQL available; do not use a production database.

<details>
<summary>日本語</summary>

# 保存した決算原本からの抽出

処理前にDBマイグレーションを適用する。通常のPostgreSQL設定を使い、新しい
Mixプロセスで上記の4コマンドを実行する。タスクはEctoとRepoだけを起動し、
収集スケジューラが既に動いている場合は実行を拒否する。Web endpointや発行元の取得は起動しない。

`--original` は保存バイト列から1試行を作る。`--retry` はその原本の最新割当試行が
失敗している場合に使う。`--regenerate` は完了試行のある原本をUUID昇順で重複なく処理する。
件数は1〜100を明示し、無制限モードは設けない。返された `next_after` を次の範囲に使う。
空の範囲ではカーソルはnull。完了試行がない待機原本は選ばない。

JSONは試行・原本・状態・失敗理由・抽出器の版を示す。処理失敗は `failed` として記録し、
コマンド実行自体の失敗にはしないため、JSONの状態を確認する。不正引数、存在しない原本、
不正な再試行対象はCLIエラーになる。取得履歴と原本バイト列は変更しない。

## 実行環境と上限

Linux、Python 3、Poppler `pdftotext`、日本語CIDフォント用の `poppler-data` を必要とする。
本番イメージとCIで導入する。OCRは行わない。画像のみ・本文なしは `empty_output`、
破損・読取不能は `unreadable` として記録する。

シェルを使わず `-enc UTF-8 -eol unix -nopgbrk` で実行し、Popplerが復元できる読順と段落を保持する。
仮想アドレス空間512 MiB、コアダンプ禁止、本文・診断ファイルの上限、タイムアウトに基づく
CPU上限を設ける。既定は20秒・本文8 MiB。`--timeout-ms`（1〜30000）と
`--max-output-bytes`（1〜8388608）で上限内の設定ができる。版の確認は追加で最大2秒。
タイムアウトと通常終了でプロセス群を終了する。非対応環境は明示的に失敗する。

失敗コードには `timeout`、`output_limit`、`invalid_text`、`extractor_unavailable`、
`process_error`、`unsupported_platform` がある。NUL、不正UTF-8、空白のみの本文を拒否する。
上限に合わせた成功本文の切り捨ては行わない。再生成失敗後も以前の成功試行を保持する。

## 本文の確認と選択

`Lens.Earnings.Extractions.latest_success(original_id)` は原本の最新成功試行を返す。
`release_text(release_id)` は選択抽出、最新対象原本、その最新試行、`stale` を返す。
識別が確定した取得成功だけを使い、原本はその短信での最初の取得日時、UUIDの順に降順で選ぶ。
旧バイト列の再取得で昇格させない。同じ原本の試行は完了順でなく割当連番で選ぶ。

新版が失敗した場合は旧版本文を `stale: true` で維持する。成功本文なしは `extraction: nil`
として短信を確認できる。最新試行の待機・成功・失敗は、選択成功本文とは独立に確認できる。
検索連携は #72 の後続段階。

## 検証

合成PDFとReportLab生成器は `test/fixtures/` にある。
`python3 -m unittest discover -s test -p pdf_runner_test.py` で日本語本文、画像のみ、
プロセス失敗、出力上限、子プロセス終了を検証する。
`test/system/earnings_offline_check.exs` は `mix run --no-start` で実行する使い捨てDB用の検証。
空のテストDBをマイグレーションし、実CLI・原本バイト列・取得件数を確認する。
PostgreSQLだけがある内部Dockerネットワークで実行し、本番DBは使わない。

</details>
