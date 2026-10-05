---
status: accepted
---

# Preserve the PDF execution boundary when removing Python

Use a small Linux C11 helper, called through an Erlang Port, to run Poppler outside the application VM. The helper owns process limits, deadlines and process-group cleanup; the Elixir adapter owns temporary files and bounded result parsing.

This removes the Python runtime dependency while keeping PDF processing failures separate from the application VM. A Port alone provides communication, but does not establish resource limits or descendant cleanup. An in-process NIF would expose the VM to native failures. The helper adds C build and maintenance work.

Keep `Lens.Earnings.PDFExtractor.extract/2`, extractor identity and acquisition/extraction history semantics. Do not fall back to unrestricted execution when the helper or required limits are unavailable. These are per-process and per-file limits, not a general sandbox or aggregate process-tree quota. See [runtime bounds and commands](../earnings-extraction.md) for the current interface and exclusions.

This records the existing implementation decision from [#91](https://github.com/9renpoto/lens/issues/91), not a new decision in the paused v0.2 discussion.

<details>
<summary>日本語</summary>

# Python削除時もPDFの実行境界を維持する

小さなLinux用C11ヘルパーをErlang Portから呼び出し、アプリケーションVMの外でPopplerを実行する。ヘルパーはプロセスの上限・期限・プロセス群の終了、Elixirアダプターは一時ファイルと上限付きの結果解析を担当する。

PDF処理の障害をアプリケーションVMから分離したまま、Pythonの実行時依存を除く。Portだけでは通信はできても資源制限や子孫の終了を保証できず、VM内のNIFではネイティブ処理の障害がVMへ影響する。ヘルパーにはCのビルド・保守作業が必要となる。

`Lens.Earnings.PDFExtractor.extract/2`、抽出器の識別、取得・抽出履歴の意味を維持する。ヘルパーや必要な上限が使えない場合に無制限実行へ切り替えない。上限はプロセス・ファイル単位であり、一般的なサンドボックスやプロセス群の総量制限ではない。現行インターフェースと保証外の条件は[実行上限とコマンド](../earnings-extraction.md)を参照する。

これは[#91](https://github.com/9renpoto/lens/issues/91)からの既存実装の判断を記録するもので、中断中のv0.2議論で新たに決めた内容ではない。

</details>
