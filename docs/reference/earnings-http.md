# Earnings HTTP transport and operator storage API

`Lens.Earnings.HTTP.fetch/2` provides the transport foundation for
[#71](https://github.com/9renpoto/lens/issues/71). It performs no database writes,
identity confirmation, scheduling, or extraction. [Source registration](https://9renpoto.github.io/lens/) and the [registered candidate collector](earnings-collector.md) are available. The collector checks source enablement and uses one shared run budget for a manual run; request cadence and daily scheduling remain follow-up work. Operators review acquisition conditions before enabling sources under [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md).

An explicit `allowed_url?` predicate is required by the transport. Without one, every URL is rejected before a request. The predicate is applied to the initial URL and each redirect destination before that destination is contacted. URLs must use HTTP(S), have a host, and contain no embedded credentials. `SourceCatalog` provides registered listings, not a document route-authorization predicate. The collector explicitly supplies a default policy accepting valid HTTP(S) URLs within 4096 bytes, including external document hosts, without restricting network addresses. Callers can supply a stricter policy. Registration alone is not a transport policy or evidence of publisher permission. See the collector reference for manual execution, policy customization and provenance persistence.

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
  hop. There are zero automatic retries. The collector applies a shared run budget;
  retry/backoff and request cadence remain follow-up work subject to publisher conditions.
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
content encoding, and connection failure. No publisher is contacted. The collector connects this layer to acquisition history and manual bounded runs.
Per-source concurrent-run exclusion, daily scheduling and capped retry/backoff remain follow-up work.

## Operator storage API (#160 / #73)

The original retrieval route remains behind the deployment's existing private operator-access boundary. This does not add authentication, ingress, public sharing or write/retry operations. Original retrieval uses the immutable RustFS reference stored on the original and RustFS runtime configuration. All responses from these actions have `Cache-Control: no-store`.

| Route | Response | Errors |
| --- | --- | --- |
| `GET /api/earnings/originals/:id` | 200 `application/pdf` with exact verified retained bytes | 404 for malformed/unknown original IDs; 503 for known originals with unavailable storage |

Storage-work listing/detail routes and their OpenAPI schemas are removed under [ADR 0013](../adr/0013-retire-interrupted-storage-recovery.md). `GET /api/earnings/storage-work` and `GET /api/earnings/storage-work/:id` now return 404. There is no replacement recovery or retry API. Use the collector's explicit errors and acquisition outcomes when reviewing a failed save. Work identifiers are not original identifiers.

The original route accepts `Accept: application/pdf`, `application/json` or `*/*`. Success is PDF and errors are JSON; callers should inspect the status and Content-Type. Other API routes retain their existing JSON negotiation. Read any retained original version by its original ID, including older versions. Verify byte size and SHA-256 through the selected backend before sending bytes. Do not refetch the publisher, fall back to a PostgreSQL copy when selected RustFS storage fails, allocate extraction attempts or mutate acquisition/history records.

Known-original failures have this strict JSON shape:

```json
{"error":"original_unavailable","original_id":"UUID","reason":"integrity_error"}
```

The finite reason set is `not_found`, `integrity_error`, `original_unavailable`, `not_configured`, `invalid_configuration`, `destination_mismatch`, `unauthorized`, `timeout`, `transport_error`, `unavailable`, `invalid_reference`, `conflict` and `storage_error`. A missing RustFS object returns 503 with `not_found`; an unknown original ID returns 404 with `{"error":"not_found"}`. Corrupt bytes return 503 with `integrity_error`. Other unlisted/structured provider failures become `storage_error`, without returning provider bodies, credentials or destination URLs. Storage errors follow the synchronous contract in ADR 0013. API behavior is independent of the deployment environment.

<details>
<summary>日本語</summary>

# 決算HTTP取得と運用者向け保存API

`Lens.Earnings.HTTP.fetch/2`は[#71](https://github.com/9renpoto/lens/issues/71)の取得基盤。
DB書込・識別確定・日次実行・抽出は行わない。[取得先登録](https://9renpoto.github.io/lens/)と[登録候補の収集処理](earnings-collector.md)は利用できる。収集側は取得先の有効状態を確認し、手動の1回の実行で共有の実行上限を適用する。巡回間隔と日次実行は後続作業に残る。運用者は [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md) に従い、取得先を有効にする前に取得条件を確認する。

HTTP取得には明示的な`allowed_url?`判定が必須で、未指定なら通信前に全URLを拒否する。初期URLと各リダイレクト先を通信前に判定する。URLはHTTP(S)、ホストあり、埋め込み認証情報なしを必須とする。`SourceCatalog`は登録一覧を提供するが、資料経路の取得許可判定は提供しない。収集側は4096バイト以内の有効なHTTP(S) URLを外部資料ホストも含めて許可する既定ポリシーを明示的に渡し、ネットワークアドレスは制限しない。呼び出し側はより厳しいポリシーを指定できる。登録だけでは取得ポリシーや発行元の許可の証跡にはならない。手動実行、ポリシーの変更、出典の永続化は収集処理の参照資料を確認する。

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
  収集側は共有の実行上限を適用する。再試行・待機と巡回間隔は発行元条件に従う後続作業。
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
収集側は取得履歴と上限付き手動実行へ接続している。取得先ごとの同時実行排他・日次実行・上限付き再試行と待機は後続作業。

## 運用者向け保存API（#160・#73）

原本取得ルートは、配備の既存の非公開運用者アクセス境界内に残る。認証・Ingress・外部共有・書込・再試行操作は追加しない。原本取得には原本に記録した不変のRustFS参照と実行時設定を使う。これらのactionの全応答に`Cache-Control: no-store`を付ける。

| ルート | 応答 | エラー |
| --- | --- | --- |
| `GET /api/earnings/originals/:id` | 200 `application/pdf`、検証済みの正確な保持バイト列 | 不正・不存在の原本IDは404。既知だが保存先が利用不可の原本は503 |

[ADR 0013](../adr/0013-retire-interrupted-storage-recovery.md)に従い、保存作業の一覧・詳細ルートとOpenAPIスキーマを削除する。`GET /api/earnings/storage-work`と`GET /api/earnings/storage-work/:id`は404を返す。代替の復旧・再試行APIは提供しない。保存失敗の確認にはCollectorの明示的なエラーと取得結果を使う。作業識別子は原本識別子ではない。

原本ルートは`Accept: application/pdf`、`application/json`、`*/*`を受理する。成功はPDF、エラーはJSONなので、呼び出し側は状態コードとContent-Typeを確認する。他のAPIルートは既存のJSON形式交渉を維持する。過去版を含む保持原本を原本IDで取得できる。送信前に選択済みbackendでサイズ・SHA-256を検証する。公開元からの再取得、選択済みRustFSの失敗時のPostgreSQLコピーへのフォールバック、抽出試行の作成、取得・履歴の変更は行わない。

既知原本の失敗は次の厳密なJSON形式を使う。

```json
{"error":"original_unavailable","original_id":"UUID","reason":"integrity_error"}
```

理由の有限集合は`not_found`、`integrity_error`、`original_unavailable`、`not_configured`、`invalid_configuration`、`destination_mismatch`、`unauthorized`、`timeout`、`transport_error`、`unavailable`、`invalid_reference`、`conflict`、`storage_error`。RustFSオブジェクト欠落は503と`not_found`、未知の原本IDは404と`{"error":"not_found"}`を返す。破損は503と`integrity_error`。その他の未登録・構造化されたprovider障害は`storage_error`に変換し、provider本文・認証情報・保存URLを返さない。保存エラーはADR 0013の同期契約に従う。APIの挙動は配備環境から独立する。

</details>
