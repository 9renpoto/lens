# Earnings HTTP run budgets

`Lens.Earnings.RunBudget` shares a finite HTTP budget across sequential listing
and document operations. `new/1` defaults to 24 HTTP requests, eight operations,
and a 120-second monotonic deadline. Configurable upper bounds are 32 requests,
16 operations, and 300 seconds; all limits must be positive integers.

Pass the returned budget into every subsequent `fetch/3`. Each call consumes an
operation, including URL-policy rejection before a network request. Each actual
request and redirect hop consumes a request. The wrapper reduces the existing
HTTP client's redirect allowance to the remaining request count and its timeout
to the remaining run duration. Exhausted budgets return an error without issuing
another request. HTTP outcomes remain unchanged for recording with
`HTTPHistory.record/1`; a successful wrapper return can contain a failed HTTP
outcome. This is sequential state, not a concurrency lock or shared counter.

`retry_delay/2` returns one-second and two-second delays for retry indices zero
and one. Nonretryable results and further retries are rejected. Numeric
`Retry-After` values from zero to 30 seconds increase the delay when necessary.
Longer values, dates, and malformed values return `:defer_retry`; callers must
defer instead of retrying earlier than the publisher requested.

This module does not sleep, retry, or persist automatically. The collector must
respect the returned delay, check the remaining budget by calling `fetch/3`,
and record each actual HTTP operation with a fresh check ID. Persistence retries
reuse that operation's ID and result without invoking HTTP again. Source
conditions may prohibit retries or require longer spacing; those conditions
take precedence. All pilot sources remain disabled pending their source review.
Source exclusion, checked-set selection, daily scheduling, and manual CLI
integration remain subsequent collection work.

Tests use local TCP servers to verify redirect accounting, deadline cancellation,
and absence of requests after exhaustion. Existing HTTP, history, and feed
ingestion regressions use their established tests.

<details>
<summary>日本語</summary>

# 決算資料のHTTP実行予算

`Lens.Earnings.RunBudget`は、逐次実行する一覧と資料のHTTP処理で有限の予算を
共有する。`new/1`の既定値はHTTP要求24回・処理8回・単調増加時計で120秒の期限。
設定できる上限は要求32回・処理16回・300秒で、すべて正の整数とする。

後続の`fetch/3`には必ず返された予算を渡す。URLポリシーによる要求開始前の
拒否も処理回数に数える。実際の要求とリダイレクトの各段階は要求回数に数える。
既存HTTPクライアントのリダイレクト上限を残り要求数に、タイムアウトを実行期限
までの残り時間に制限する。予算を使い切った場合は新たな要求を送らずエラーを
返す。HTTP結果は`HTTPHistory.record/1`で保存できる形を保つ。ラッパーが成功を
返してもHTTP結果自体は失敗の場合がある。逐次実行用の状態であり、並行実行の
ロックや共有カウンターではない。

`retry_delay/2`は再試行番号0・1に対して1秒・2秒の待機時間を返す。再試行不可の
結果とそれ以上の再試行は拒否する。数値の`Retry-After`が0〜30秒なら、必要に
応じて待機を延ばす。より長い値・日時形式・不正な値では`:defer_retry`を返す。
呼び出し側は後の実行に回し、発行元の指定より早く再試行しない。

このモジュールは自動で待機・再試行・保存を行わない。収集側は返された待機時間
を守り、`fetch/3`で残り予算を確認し、実際のHTTP処理ごとに新しい確認IDで保存
する。保存の再試行は同じIDと結果を再利用し、HTTPを再実行しない。取得先の条件
が再試行を禁じたり、より長い間隔を要求したりする場合は、その条件を優先する。
取得元の評価が完了するまで全パイロットソースは無効のまま。重複実行防止・確認
対象の選択・日次スケジュール・手動CLIへの接続は後続の収集実装で扱う。

ローカルTCPサーバーでリダイレクトの計数・期限による中断・予算超過後に要求が
ないことを検証する。既存のHTTP・履歴保存・フィード収集は既存テストで回帰検証
する。

</details>
