# Earnings HTTP check history

`Lens.Earnings.HTTPHistory.record/1` stores one immutable check for each actual
HTTP operation. Supply a stable `check_id`, `issuer_code`, requested `url`,
`checked_at`, and the result of `Lens.Earnings.HTTP.fetch/2`. Reuse the check ID
only when retrying persistence of that same operation. A new HTTP operation
needs a new ID. Conflicting facts return an error rather than rewriting history.

The requested URL, final URL, HTTP status, request count, response headers,
failure reason, and retryability remain distinct facts. `published_on` is an
optional publisher date; `checked_at` records acquisition time. Unknown dates
stay absent. Metadata can retain listing labels and pending identity evidence.
Metadata and headers must each encode as JSON within 32 KiB.
JSON-backed facts are normalized before comparison, so atom keys and
JSON-encodable values match the representation reloaded from PostgreSQL.
Non-UTF-8 response header values containing HTTP obs-text are retained as
`%{"encoding" => "base64", "value" => "..."}` so their exact bytes can be recovered.
UTF-8 header values use strings. The 32 KiB bound includes the encoded representation;
header values containing NUL are rejected.

A successful PDF check atomically stores the exact original bytes and an
acquisition identified by `http:` followed by the check ID. Its digest and byte
size must match the retained original. Identical downloads share an original
but have separate acquisition histories. Changed bytes preserve both originals.
Missing release identity retains the original for later confirmation.

A failed PDF request records an acquisition failure without replacing any prior
original. A 304 response, listing check, or rejection before any request records
only a check; it does not fabricate a PDF acquisition. Unsuccessful results
containing bytes and successful PDFs without the `%PDF-` marker are rejected.

Failure reasons must agree with the HTTP status, headers, request count, and
retryability. Transport and policy failures have no response status or headers;
response failures require the status appropriate to their reason. Size-limit
failures may retain a 200 response or have no response facts when the streaming
body exceeds the limit. A 200 size failure requires a parseable `content-length`
greater than the minimum permitted limit of one byte; smaller configured limits
remain supported. Encoding and PDF failures cannot advertise a length beyond the
maximum permitted limit, and PDF classification requires identity encoding.
Contradictory facts return a validation error before any
records are written.
An `unsupported_encoding` failure requires a non-identity `content-encoding`
value in the normalized response headers.

## Result contract

Acquisition and persistence share `HTTPResponseFacts` for header bytes, kind size
caps, encoding interpretation, and redirect resolution. Network execution and
transactional persistence remain separate. Header evidence is interpreted from
raw strings or the lossless Base64 representation after JSON normalization.

All outcomes require an evaluated final URL and 0–4 started requests. Only
success contains bytes; successful PDFs require the `%PDF-` marker. For PDF and
listing, maximum permitted sizes are 20 MiB and 2 MiB respectively.

| Outcome / failure reason | Started requests | Response evidence | Retryable |
|---|---|---|---|
| `success` | 1–4 | 200, identity encoding (or absent), retained bytes and advertised size within the kind cap | No |
| `not_modified` | 1–4 | 304; size and encoding headers are not inspected | No |
| `invalid_options` | 0 | No status, empty headers | No |
| `url_not_allowed` | 0–4 | No status, empty headers | No |
| `timeout` | 0–4 | No status, empty headers | Yes |
| `transport_error` | 0–4 | No status, empty headers; includes worker exit during policy evaluation | Yes |
| `interrupted` | 1–4 | No status, empty headers | Yes |
| `too_large` | 1–4 | No response facts for streaming overflow, or 200 with integer Content-Length greater than 1 | No |
| `unsupported_encoding` | 1–4 | 200, non-identity encoding evidence, no advertised size beyond the kind cap | No |
| `non_pdf` | 1–4 | PDF kind, 200, identity encoding, no advertised size beyond the PDF cap | No |
| `invalid_redirect` | 1–4 | 301/302/303/307/308; Location absent or unresolvable against final URL | No |
| `redirect_limit` | 1–4 | 301/302/303/307/308; Location need not be valid because the limit is checked first | No |
| `http_error` | 1–4 | Status other than 200, 304, or a redirect | Only 429 or 5xx |

A relative, empty, or non-HTTP Location can resolve successfully; URL permission
is a separate decision. Such a target cannot substantiate `invalid_redirect`.
Missing or unparsable Content-Length does not establish size overflow.

The result omits the configured `max_bytes` and redirect limit. Persistence
rejects contradictions provable from retained facts, while allowing outcomes
compatible with any permitted configuration. For example, Content-Length 2 can
substantiate `too_large` with a one-byte limit, and the first redirect can exhaust
a zero-redirect limit. Exact execution-limit validation requires additional
recorded facts and remains subsequent work.

For `url_not_allowed`, the final URL retains the evaluated target, including
non-HTTP targets rejected after a redirect. Timeout and interruption results also
retain a non-HTTP target evaluated before the deadline or worker exit.
This bounded provenance text records
the evaluated destination. A failed acquisition still uses the requested
HTTP(S) URL. Every check requires its evaluated final URL, including failures
before the first request. Other outcomes require an HTTP(S) final URL.

PostgreSQL prevents updates and deletions of checks and verifies their linked
acquisition facts. Check validation, original retention, acquisition creation,
and check insertion share one transaction. This layer does not activate sources,
schedule requests, or infer release identity. Those steps remain separate.

<details>
<summary>日本語</summary>

# 決算資料のHTTP確認履歴

`Lens.Earnings.HTTPHistory.record/1`は、実際のHTTP処理ごとに変更不能な確認履歴を
保存する。安定した`check_id`、`issuer_code`、要求した`url`、`checked_at`と、
`Lens.Earnings.HTTP.fetch/2`の結果を渡す。同じ処理の保存を再試行するときだけ
確認IDを再利用する。新しいHTTP処理には新しいIDを使う。記録内容が衝突した
場合は、履歴を書き換えずエラーを返す。

要求URL・最終URL・HTTPステータス・要求回数・応答ヘッダー・失敗理由・再試行
可否は個別の事実として残す。`published_on`は任意の公開日、`checked_at`は
取得日時であり、不明な日付は空欄のままにする。メタデータには一覧のラベルや
同定待ちの根拠を残せる。メタデータとヘッダーは、それぞれJSONとして32 KiB
以内に収まる必要がある。
JSON形式の事実は比較前に正規化し、atomキーやJSONに変換できる値を
PostgreSQLから再取得した表現と一致させる。
UTF-8ではないHTTP obs-textの応答ヘッダー値は、正確なバイト列を復元できるよう
`%{"encoding" => "base64", "value" => "..."}`として保持する。UTF-8のヘッダー値は
文字列で保存する。32 KiBの上限はエンコード後の表現に適用し、NULを含む
ヘッダー値は拒否する。

PDF取得成功時は、原本の正確なバイト列と、確認IDに`http:`を付けた取得履歴を
同一トランザクションで保存する。ダイジェストとバイト数は保存原本と一致する
必要がある。同一内容の再取得は原本を共有し、取得履歴は個別に残す。内容が
変わった場合は両方の原本を保持する。資料の同定情報がなくても、後から確認
できるよう原本を残す。

PDF要求の失敗は取得失敗履歴に残し、以前の原本を置き換えない。304応答・一覧
確認・要求開始前の拒否は確認履歴だけを保存し、PDF取得履歴を作り出さない。
失敗結果にバイト列が含まれる場合や、成功PDFに`%PDF-`がない場合は拒否する。

失敗理由はHTTPステータス・ヘッダー・要求回数・再試行可否と整合する必要がある。
通信やポリシーによる失敗は応答ステータスとヘッダーを持たず、応答に由来する
失敗は理由に応じたステータスを必要とする。サイズ上限の超過は200応答を保持
する場合と、受信中の本文が上限を超えたため応答情報を持たない場合がある。
200応答のサイズ超過は、許可する上限の最小値である1バイトを超える、整数として
解釈できる`content-length`を必要とする。小さな取得上限も利用できる。
エンコーディング・PDF判定の失敗は最大許容上限を超える長さを持てず、
PDF判定の失敗はidentityエンコーディングを必要とする。
矛盾する事実は、履歴を書き込む前に検証エラーとして返す。
`unsupported_encoding`の失敗は、正規化した応答ヘッダーにidentity以外の
`content-encoding`値を必要とする。

## 結果契約

取得処理と保存処理は、ヘッダーのバイト列・種別ごとのサイズ上限・エンコーディング
の解釈・リダイレクト先の解決を`HTTPResponseFacts`で共有する。通信の実行と
トランザクションによる保存は別々に担当する。ヘッダーの根拠はJSON正規化後の
生の文字列または情報を失わないBase64表現から読み取る。

すべての結果に評価した最終URLと0〜4回の開始済み要求数が必要である。
バイト列を持つのは成功結果だけで、PDF成功には`%PDF-`が必要である。
PDFと一覧の最大許容サイズは、それぞれ20 MiBと2 MiBである。

| 結果／失敗理由 | 開始済み要求数 | 応答の根拠 | 再試行可能 |
|---|---|---|---|
| `success` | 1〜4 | 200、identityエンコーディングまたはヘッダーなし、保持バイト数と広告サイズが種別上限以内 | いいえ |
| `not_modified` | 1〜4 | 304。サイズとエンコーディングのヘッダーは検査しない | いいえ |
| `invalid_options` | 0 | ステータスなし、空ヘッダー | いいえ |
| `url_not_allowed` | 0〜4 | ステータスなし、空ヘッダー | いいえ |
| `timeout` | 0〜4 | ステータスなし、空ヘッダー | はい |
| `transport_error` | 0〜4 | ステータスなし、空ヘッダー。ポリシー評価中のworker終了を含む | はい |
| `interrupted` | 1〜4 | ステータスなし、空ヘッダー | はい |
| `too_large` | 1〜4 | 受信中の超過では応答情報なし、または200かつ1より大きい整数のContent-Length | いいえ |
| `unsupported_encoding` | 1〜4 | 200、identity以外の根拠、広告サイズが種別上限を超えない | いいえ |
| `non_pdf` | 1〜4 | PDF種別、200、identity、広告サイズがPDF上限を超えない | いいえ |
| `invalid_redirect` | 1〜4 | 301/302/303/307/308。Locationが欠落、または最終URLに対して解決不能 | いいえ |
| `redirect_limit` | 1〜4 | 301/302/303/307/308。上限検査が先なのでLocationが有効とは限らない | いいえ |
| `http_error` | 1〜4 | 200・304・リダイレクト以外のステータス | 429または5xxのみ |

相対・空・非HTTPのLocationも解決できる場合があり、URLの許可判定は別である。
このような宛先は`invalid_redirect`の根拠にならない。
Content-Lengthの欠落や解析不能な値は、サイズ超過の根拠にならない。

結果には設定した`max_bytes`とリダイレクト上限が含まれない。保存層は保持した
事実から確定する矛盾を拒否し、許可されるいずれかの設定で起こり得る結果は
受け入れる。例えば1バイトの上限ではContent-Length 2が`too_large`の根拠となり、
リダイレクト上限0では初回のリダイレクトで上限に到達する。
実行上限との完全な一致の検証には追加情報の保存が必要であり、後続作業とする。

`url_not_allowed`の最終URLには評価した宛先を残し、リダイレクト後に拒否した
非HTTPの宛先も保持する。タイムアウト・中断時も、期限切れやworker終了前に
評価した非HTTPの宛先を保持する。評価した宛先を、長さを制限した出典情報として保存する。
取得失敗履歴には引き続き要求したHTTP(S) URLを使う。
最初の要求前の失敗を含め、すべての確認履歴は評価した最終URLを必要とする。
他の結果はHTTP(S)の最終URLを必要とする。

PostgreSQLで確認履歴の更新・削除を防ぎ、関連する取得履歴との整合性を検証する。
確認内容の検証・原本保存・取得履歴作成・確認履歴挿入は同一トランザクションで
実行する。この層はソースの有効化・要求スケジュール・資料同定の推定を行わず、
それらは別の工程で扱う。

</details>
