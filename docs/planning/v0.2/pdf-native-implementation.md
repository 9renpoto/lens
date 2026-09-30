# Native PDF runner implementation (#93)

Stack: #96 → #93 implementation → #94 release proof. Python remains installed
and its reference runner/tests remain available until the #94 gates pass.

The C11 helper runs probe and extraction in separate sessions with pre-exec
RLIMITs, monotonic phase deadlines and group cleanup after every phase. Its
stdout carries one status line, never PDF text. It sets Linux
`PR_SET_CHILD_SUBREAPER` and reaps adopted same-group descendants after killing
the group, so cleanup does not depend on PID 1 reaping zombies. Unavailable
subreaper support fails closed with `unsupported_platform`. The adapter limits the status
to 256 bytes and reads text/version files after helper exit. Unicode blankness
matches Python's whitespace set, including U+001C–U+001F.

A worker monitors the caller so ordinary caller death triggers cancellation
without deleting files before helper exit. Cancellation first writes a byte to
the helper's stdin. After a two-second grace, a separate invocation of the same
native helper sends TERM and CONT; if necessary it sends KILL after another
two seconds. This control invocation avoids a runtime compiler, shell command,
process library or `/bin/kill` package dependency. SIGKILL of the VM/helper,
uninterruptible kernel sleep and descendants escaping the process group remain
outside the guarantee. A handled helper failure completes an extraction attempt;
VM failure recovery remains outside this refactor.

## Commands and current evidence

On Linux with a C compiler, Elixir/OTP and Poppler/poppler-data:

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror priv/pdf_runner.c -o priv/pdf_runner
test/pdf_native_runner_check.sh
mix compile --warnings-as-errors
elixir -pa "_build/test/lib/*/ebin" test/pdf_adapter_check.exs
mix test
```

The compiler and native process checks ran in `lens-pdf-tools` with network
access disabled. Adapter checks ran in `lens-extraction-check` with network
access disabled. Fourteen adapter cases cover real Japanese/paragraph text,
image-only PDF, blank/invalid text, missing helper, unsupported OS, malformed
and oversized responses, caller death and a stuck helper's outer deadline.
The process checks also passed with Docker `--init=false` and PID 1 set to
`/bin/sleep`, after reproducing the pre-fix zombie leak there. They cover probe/extraction descendants on normal and timeout
exit (no delayed marker and no `/proc` entry), actual AS/CORE/CPU/FSIZE values,
AS failure, CPU termination, overflow precedence and pipe closure.

A disposable PostgreSQL 17.6 database on an internal Docker network was used
for `mix compile --warnings-as-errors` and all 172 repository tests: passed.
This is regression evidence, not the final PostgreSQL 18 release gate. The
Dockerfile now builds the helper but still retains Python. #94 must provide
same-environment differential samples, image-size benefit, supported amd64
release proof without Python, coverage/dialyzer and offline CLI/history checks
before dependencies are removed. No originals or historical attempts are rewritten.

<details>
<summary>日本語</summary>

# native PDFランナー実装 (#93)

スタックは #96 → #93実装 → #94 release検証。#94のゲート合格まではPython導入と
比較用ランナー・テストを残す。

C11ヘルパーは版確認と抽出を別セッションで実行し、exec前のRLIMIT、単調時計の期限、
全段階終了後の群終了を適用する。stdoutは状態1行のみで本文を流さない。
Linux `PR_SET_CHILD_SUBREAPER` で同じ群の子孫を引き取り、群終了後に回収するため、
PID 1のゾンビ回収に依存しない。subreaperが利用できなければ `unsupported_platform`。
アダプターは状態256 bytes、終了後の本文・版ファイルを扱う。Unicode空白判定は
U+001C–U+001Fを含むPythonの空白集合に対応する。

workerが呼出元を監視し、通常の呼出元終了で取消し、ヘルパー終了前にファイルを削除しない。
まずstdinへ1 byteを送り、2秒後も終了しなければ同じnativeヘルパーの別起動からTERMとCONT、
さらに2秒後に必要ならKILLを送る。runtimeコンパイラー、shellコマンド、追加ライブラリー、
`/bin/kill`パッケージに依存しない。VM/ヘルパーのSIGKILL、kernelの割込み不能待機、
群から離れる子孫は保証外。処理可能なヘルパー失敗は抽出試行を完了し、VM障害回復は範囲外。

## コマンドと現在の根拠

LinuxのCコンパイラー、Elixir/OTP、Poppler/poppler-dataで実行する。

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror priv/pdf_runner.c -o priv/pdf_runner
test/pdf_native_runner_check.sh
mix compile --warnings-as-errors
elixir -pa "_build/test/lib/*/ebin" test/pdf_adapter_check.exs
mix test
```

コンパイル・プロセス検証は通信なしの `lens-pdf-tools`、アダプターは通信なしの
`lens-extraction-check` で実行。14ケースで実日本語・段落、画像のみPDF、空白・不正本文、
ヘルパー不在、非対応OS、不正・過大応答、呼出元終了、停止ヘルパーの外側期限を検証する。
Docker `--init=false`、PID 1を `/bin/sleep` にした環境で修正前のゾンビ残留を再現し、
修正後のプロセス検証が成功した。版確認・抽出の通常終了/期限超過時の子孫について遅延markerと `/proc` 不在、
AS/CORE/CPU/FSIZE実値、AS失敗、CPU終了、超過優先順位、pipe閉鎖を確認する。

内部Dockerネットワークの使い捨てPostgreSQL 17.6で
`mix compile --warnings-as-errors` と全172テストが成功した。
これは回帰の根拠で、最終PostgreSQL 18 releaseゲートではない。Dockerfileはヘルパーを
ビルドするがPythonは残す。#94で同一環境の比較生データ、容量削減、対応amd64のPythonなし
release、coverage/dialyzer、offline CLI/履歴を実証してから依存を削除する。
原本・過去試行を書き換えない。

</details>
