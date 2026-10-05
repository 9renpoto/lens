# Bounded earnings HTTP transport

`Lens.Earnings.HTTP.fetch/2` provides the transport foundation for
[#71](https://github.com/9renpoto/lens/issues/71). It performs no database writes,
identity confirmation, scheduling, or extraction. The collector must enforce
source activation and request cadence before invoking it. Source registration
and collector integration remain [planned work](../tasks/v0.2.md).
An explicit `allowed_url?` predicate is required. Without one, every URL is
rejected before a request. The predicate is applied to the initial URL and each
redirect destination before that destination is contacted. URLs must use
HTTP(S), have a host, and contain no embedded credentials. Production document
policies must also apply the catalog's reviewed-document route predicate.

## Bounds and response handling

- `kind: :pdf` is the default, with a 20 MiB (20,971,520 byte) maximum.
  `kind: :listing` has a 2 MiB (2,097,152 byte) maximum. `max_bytes` can lower the
  corresponding cap but cannot increase it.
- `timeout_ms` defaults to 20,000 and accepts 1–30,000. One monotonic deadline
  covers the entire operation, including initial URL-policy evaluation, connection, receive, and all redirects;
  activity and redirects do not reset it. A monitored worker is cancelled on
  timeout or caller termination. Interrupted/failed data is never returned as a
  successful original. An optional absolute monotonic-millisecond `deadline` can
  shorten this bound. Connection options stay fixed to reuse one Finch pool.
- `max_redirects` accepts 0–3 and defaults to 3: at most four HTTP attempts per
  invocation. Redirects are followed explicitly, with policy checks before each
  hop. There are zero automatic retries; later retry/backoff and run budgets are
  collector responsibilities, subject to publisher conditions.
- Req streams each body chunk into a byte-counted accumulator. Oversized
  Content-Length is rejected, and actual chunks are checked even without that
  header. Error and redirect bodies are not retained. Automatic decompression
  and content decoding are disabled; the client requests identity encoding and
  rejects other Content-Encoding values to preserve exact PDF bytes.
- Only status 200 returns bytes. PDF acquisition checks the `%PDF-` prefix,
  independently of Content-Type. This is a format check, not structural PDF
  validation; extraction can still fail and must remain a separate outcome.
  Listing acquisition returns bounded raw bytes for HTML discovery. A 304
  records an unchanged check with no invented downloaded bytes.

Optional `headers` carry conditional validators such as `if-none-match` and
`if-modified-since`. Successful response headers expose returned validators for
future checks. The transport neither creates acquisition identifiers nor retries
persistence; the collector must allocate one identifier per actual download and
reuse it only when retrying that same persistence operation.

Cross-origin redirects retain only `accept`, `accept-language`, and `user-agent`
from caller headers. Credentials, custom headers, and conditional validators are
removed; same-origin redirects preserve caller headers. The origin includes scheme,
host, and port. Content-Encoding identity tokens are compared without case sensitivity.

## Result contract

The result contains `outcome` (`:success`, `:not_modified`, or `:failed`),
`failure_reason`, `http_status`, `headers`, `bytes`, `final_url`, `requests`, and
`retryable`. `bytes` is present only on success. `final_url` identifies the last
evaluated target; a denied redirect destination was not contacted. HTTP status
and headers are available when a response completes; transport errors and total
timeouts can leave them unknown. `requests` counts started HTTP attempts,
including redirects, independently of persistence.

Failure reasons distinguish `:too_large`, `:non_pdf`, `:unsupported_encoding`,
`:http_error`, `:interrupted` (connection closed during reception), `:timeout`,
`:transport_error`, `:redirect_limit`, `:invalid_redirect`, `:url_not_allowed`,
and `:invalid_options`. HTTP 429/5xx, interrupted connections, timeouts, and
transport errors are retryable indications, not instructions to poll immediately.
Other failures require configuration/material review. Existing originals and
history are untouched because this layer does not write to storage.

Tests use actual local TCP/HTTP responses for exact bytes, chunked size bounds,
advertised size rejection, conditional headers, 304, HTTP errors, interrupted
responses, denied/relative/looping redirects, total deadlines, caller termination,
content encoding, and connection failure. No publisher is contacted. Connecting
this layer to acquisition history, per-source exclusion, daily/manual execution,
and capped retry/backoff remains subsequent stack work.

<details>
<summary>日本語</summary>

# 上限付きの決算HTTP取得

`Lens.Earnings.HTTP.fetch/2`は[#71](https://github.com/9renpoto/lens/issues/71)の取得基盤。
DB書込・識別確定・日次実行・抽出は行わない。収集側は呼び出し前に取得元の有効状態と
巡回間隔を確認する。取得先の登録と収集への接続は[計画中の作業](../tasks/v0.2.md)。
明示的な`allowed_url?`判定が必須で、指定がなければ通信前に全URLを拒否する。
初期URLと各リダイレクト先を、その先へ通信する前に判定する。URLはHTTP(S)、
ホストあり、埋め込み認証情報なしを必須とする。本番資料の判定では台帳の検証済み
資料経路の判定も適用する必要がある。

## 上限と応答処理

- 既定の`kind: :pdf`は20 MiB（20,971,520バイト）まで。`kind: :listing`は
  2 MiB（2,097,152バイト）まで。`max_bytes`は該当上限を下げる指定だけを許容する。
- `timeout_ms`は既定20,000、指定範囲1〜30,000。初回URLポリシー評価・接続・受信・全リダイレクトを
  一つの単調時計の期限で管理し、通信やリダイレクトで期限を更新しない。
  期限切れ・呼び出し元終了で監視中のワーカーを停止する。
  中断・失敗したバイト列を成功原本として返さない。任意の絶対期限`deadline`
  （単調時計のミリ秒値）で上限を短縮できる。接続設定を固定しFinchプールを再利用する。
- `max_redirects`は0〜3、既定3で、呼び出しごとにHTTP試行は最大4回。
  各宛先の通信前に判定し、明示的にリダイレクトする。自動再試行は0回。
  後続の再試行・待機と実行上限は発行元条件に従う収集側の責務。
- Reqの受信チャンクをバイト数付きで蓄積する。Content-Length超過を拒否し、
  ヘッダー欠落時も実チャンクの量を確認する。エラー・リダイレクト本文は保持しない。
  自動展開・本文変換を無効にし、identity圧縮方式を要求して他のContent-Encodingを
  拒否することでPDFバイト列を保持する。
- 200のみバイト列を返す。PDFはContent-Typeと独立に`%PDF-`接頭辞を確認する。
  構造の検証ではなく、抽出は失敗し得るため別の結果として扱う。
  一覧は上限内の生バイト列をHTML発見処理へ渡す。304は未変更確認として扱い、
  ダウンロードしたバイト列を捏造しない。

`headers`には`if-none-match`・`if-modified-since`などの条件付き取得情報を渡せる。
成功応答のヘッダーから次回用の検証子を参照できる。取得識別子の生成や保存再試行は
行わない。収集側は実際のダウンロードごとに識別子を割り当て、その保存処理を
再試行する場合だけ同じ識別子を再利用する。

別オリジンへのリダイレクトでは、呼び出し側のヘッダーのうち`accept`・
`accept-language`・`user-agent`だけを引き継ぐ。認証情報・独自ヘッダー・条件付き
検証子は除去し、同一オリジンでは維持する。オリジンはscheme・host・portで判定する。
Content-Encodingのidentity値は大文字・小文字を区別せず比較する。

## 結果の契約

結果は`outcome`（`:success`・`:not_modified`・`:failed`）、`failure_reason`、
`http_status`、`headers`、`bytes`、`final_url`、`requests`、`retryable`を含む。
`bytes`は成功時のみ。`final_url`は最後に評価した宛先であり、拒否した
リダイレクト先には通信していない。応答完了時には状態・ヘッダーを参照できるが、
通信エラー・期限切れでは不明になり得る。`requests`はリダイレクトを含めた
開始済みHTTP試行数で、保存処理とは独立する。

失敗理由は`:too_large`・`:non_pdf`・`:unsupported_encoding`・`:http_error`・
`:interrupted`（受信中の接続切断）・`:timeout`・`:transport_error`・
`:redirect_limit`・`:invalid_redirect`・`:url_not_allowed`・`:invalid_options`を区別する。
429・5xx・受信中断・期限切れ・通信エラーは再試行可能の目安であり、即時巡回の指示
ではない。他の失敗は設定や資料の確認が必要。この層は保存しないため既存原本・履歴を
変更しない。

実際のローカルTCP/HTTP応答で、正確なバイト列、チャンク量、申告サイズ超過、
条件付きヘッダー、304、HTTP失敗、受信中断、拒否・相対・循環リダイレクト、
全体期限、呼び出し元終了、圧縮方式、接続失敗を検証する。発行元には通信しない。
取得履歴・企業別排他・日次と手動実行・上限付き再試行と待機への接続は後続作業。

</details>
