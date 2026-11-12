# Registered earnings candidate collection

`Lens.Earnings.Collector.run/1` performs one sequential, bounded run over enabled database-backed earnings sources. Target `active` does not control source enablement. Configure `LENS_RUSTFS_ENDPOINT`, `LENS_RUSTFS_BUCKET`, `LENS_RUSTFS_ACCESS_KEY_ID` and `LENS_RUSTFS_SECRET_ACCESS_KEY` before running collection; missing or invalid configuration returns `{:error, :not_configured}` or `{:error, :invalid_configuration}` before publisher requests. Originals retain one immutable RustFS reference. Prepare the [current database schema](../deployment.md#database-initialization) before starting the collector. Run it manually with:

```sh
mix run -e 'IO.inspect(Lens.Earnings.Collector.run())'
```

Registration and acquisition conditions are described in [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md). The default URL policy accepts absolute HTTP(S) URLs without credentials within 4096 bytes, including external document hosts; it is not a network-address restriction. Deploy within the existing private operator access boundary. Callers can supply `allowed_url?: fn url -> ... end` to restrict destinations. The same policy applies to initial requests and every redirect. Discovery ignores credential-bearing links and follows actual PDF anchors, resolving relative links against the final listing response URL.

One run shares `RunBudget` limits: 24 HTTP requests including redirects, 8 operations and a 120-second deadline by default. Override `max_requests`, `max_operations` and `timeout_ms` within the existing run-budget bounds. Each request retains the existing 20-second timeout, three-redirect cap, 2 MiB listing cap and 20 MiB PDF cap. The run stops before exceeding its budget and does not install a daily scheduler. Each accepted PDF uses one conditional RustFS write and one verification read, with each timeout capped to half the remaining run deadline. Publisher request and operation counts exclude object requests. If less than two milliseconds remain before saving, record a failed acquisition without object I/O and stop with `:run_deadline_exceeded`. After fetching a listing, collection discovers only the ordered prefix of distinct PDF links that can fit in the remaining operation budget; a longer archive does not invalidate that prefix, and the unvisited suffix is not treated as processed. Every eligible invocation discovers the current listing again and acquires that bounded prefix in document order until the budget is exhausted. It does not yet select the latest reporting release, track new listings or guarantee fairness across runs.

The return value is `{:ok, %{checks: checks, errors: errors, budget: budget, stopped: reason}}`; invalid budgets return `{:error, :invalid_budget}`. Callers may inject a matching `rustfs: client` for controlled validation. Checks are returned in operation order. HTTP failures are recorded and do not block other links or sources. Discovery failures appear in `errors`; budget exhaustion appears in `stopped`. Persistence failure stops the run with `:persistence_failed` rather than continuing acquisition without durable history. No automatic publisher HTTP retries are added. A storage failure records a failed acquisition with a safe `storage_` failure reason, adds `{:storage_failed, reason}` to the source's `errors`, and stops the whole run with `:storage_failed`. It creates no original or successful PDF check. Failure to persist this outcome stops with `:persistence_failed`. No durable payload staging, storage retry or source exclusion survives the run. A later explicitly invoked collection is a new observation, not recovery of the previous download. See [ADR 0013](../adr/0013-retire-interrupted-storage-recovery.md).

Every persisted check retains source ID, target ID and the registered listing URL in `metadata`. PDF checks also retain the listing check ID, final listing response URL, observed href, resolved document URL, anchor text and headings. Listing checks retain their final response URL. Configuration edits or disablement do not rewrite these snapshots. For an accepted PDF, validate the HTTP observation before object I/O and keep the bytes only in memory until the conditional save and size/SHA-256 verification finish. Then atomically insert the original with its immutable RustFS reference, acquisition and immutable HTTP check. A database commit failure stops the run and can leave an unreferenced immutable RustFS object; do not delete it as cleanup. A later identical conditional write verifies and reuses it. Process death can lose the in-memory observation without creating a completed acquisition. Successful PDF checks reference immutable, byte-deduplicated originals through an acquisition with no release identity. Repeated runs create distinct checks and acquisition attempts while identical bytes reuse an original. Started PDF failures retain their failure acquisition; 304 responses and failures before a request do not fabricate acquisitions.

Collection does not invoke extraction, classification or operator adoption. Use the [bounded value-validation procedure](earnings-value-validation.md) to inspect collected originals and search results.

## Acquire a verified new PDF for notification RSS

Use a separate current-schema database and RustFS bucket for verification. The
person specifying the source verifies the listing, the publisher's conditions,
the PDF URL, and the release's publication time. Keep actual identifiers, URLs,
and evidence in private operational records. Pass the enabled registered source
ID and the complete resolved PDF URL from its listing, including any query
string, as positional arguments. Use the reviewed final URLs for both
requests. Record the start time in UTC. This invocation starts only the database
and HTTP dependencies and leaves scheduled ingestion idle.

```sh
mix lens.earnings.collect SOURCE_ID 'https://publisher.invalid/selected.pdf?edition=2'
```

The run requires exactly one matching anchor. A missing or ambiguous match,
an unreadable listing, an exhausted budget, or an unsuccessful HTTP request
stops the run. Redirects also stop the run. Review the destination before updating
the registered listing or specifying a different PDF URL present in the listing.
The command validates the source ID and URL format before collecting. It reports
the recorded check IDs and outcomes, and exits with an error if collection stops.
Callers using `Collector.run_selected/3` can also supply an `allowed_url?` policy
for both requests. Inspect the result privately. Proceed only with a successful
PDF check for the selected URL. After interruption, inspect `earnings_http_checks`
for the source ID in `metadata` and the run's time window. Use the PDF check's
`acquisition_id` to find its row in `earnings_acquisitions`. If there is no PDF
check, inspect acquisitions by issuer, exact URL, and time for any storage
failure. Continue from a successful record only after verifying its original.
If a database commit fails after an object write, follow the storage guidance above.

Use the successful PDF check's acquisition row ID to find the original ID and
the provenance acquisition ID, as in the [value-validation procedure](earnings-value-validation.md).
Retrieve the exact retained original and verify it against the selected release.
Run `mix lens.earnings.extract --original ORIGINAL_ID`, then review the extracted
text and use `Lens.Earnings.confirm_identity/2` with the provenance acquisition
ID and the identity supported by the PDF. Stop if the original is unavailable,
extraction fails, or identity is uncertain. Read the [notification RSS](earnings-feed.md)
and verify the item, full text, original link, and GUID across repeated reads.

A collection rerun requests the PDF again and records a new acquisition attempt.
Identical bytes reuse the retained original. Confirming the same release identity
in the same database reuses its UUID and RSS GUID. Resume interrupted downstream
steps from a successful acquisition when its original and provenance can be
verified. Preserve release records and consumer history. Synthetic verification
covers the isolated procedure. Production delivery and the next poll's no-resend
check require separate operational acceptance.

<details>
<summary>日本語</summary>

# 登録済み決算資料候補の収集

`Lens.Earnings.Collector.run/1` は、有効なDB管理の決算取得先を逐次処理する、上限付きの1回の実行を提供する。対象の `active` は取得先の有効状態を制御しない。`LENS_RUSTFS_ENDPOINT`、`LENS_RUSTFS_BUCKET`、`LENS_RUSTFS_ACCESS_KEY_ID`、`LENS_RUSTFS_SECRET_ACCESS_KEY`を設定してから収集を実行する。設定不足・不正設定は公開元通信前に`{:error, :not_configured}`または`{:error, :invalid_configuration}`を返す。原本は一つの不変のRustFS参照を持つ。収集開始前に[現行DBスキーマ](../deployment.md#database-initialization)を準備する。手動実行は次のとおり。

```sh
mix run -e 'IO.inspect(Lens.Earnings.Collector.run())'
```

登録と取得条件は [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md) に記載する。既定のURLポリシーは、認証情報を含まない4096バイト以内の絶対HTTP(S) URLを外部資料ホストも含めて許可し、ネットワークアドレスの制限は行わない。既存の非公開の運用者アクセス境界内で配置する。呼び出し側は `allowed_url?: fn url -> ... end` で取得先を制限できる。同じポリシーを最初のリクエストと各リダイレクト先に適用する。発見処理は認証情報を含むリンクを無視し、実際のPDFリンクを追跡して、相対リンクを一覧応答の最終URLから解決する。

1回の実行は `RunBudget` の上限を共有する。既定はリダイレクトを含む24リクエスト、8操作、120秒の期限。既存の実行上限内で `max_requests`、`max_operations`、`timeout_ms` を指定できる。各リクエストは既存の20秒タイムアウト、3回のリダイレクト上限、一覧2 MiB・PDF 20 MiBの上限を維持する。上限超過前に停止し、日次スケジューラーは追加しない。受理PDFごとにRustFSへの条件付き書込1回と検証読取1回を行い、各タイムアウトを実行期限の残り時間の半分までに制限する。公開元通信のリクエスト・操作数にはオブジェクト通信を含めない。保存前の残り時間が2ミリ秒未満の場合は、通信せず失敗取得を記録し、`:run_deadline_exceeded`で停止する。一覧取得後は、残り操作予算に収まる、掲載順の異なるPDFリンクの先頭部分だけを発見する。長い過去一覧が続いてもその先頭部分を無効にせず、未走査の後続部分を処理済みとも扱わない。対象となる各実行で現在の一覧を再発見し、この上限付き先頭部分を掲載順に取得する。最新の決算回の選択、新規掲載の追跡、実行間の公平性はまだ提供しない。

戻り値は `{:ok, %{checks: checks, errors: errors, budget: budget, stopped: reason}}`。不正な上限は `{:error, :invalid_budget}` を返す。制御された検証では、保存先の一致する`rustfs: client`を指定できる。確認記録は操作順に返す。HTTP失敗は記録し、ほかのリンクや取得先を止めない。発見失敗は `errors`、上限到達は `stopped` に残す。永続化失敗は履歴を保存できないまま取得を続けず、`:persistence_failed` で実行を止める。公開元HTTPの自動再試行は追加しない。保存障害では、安全な`storage_`失敗理由を持つ失敗取得を記録し、当該取得先の`errors`に`{:storage_failed, reason}`を追加して、実行全体を`:storage_failed`で停止する。原本や成功PDF確認は作らない。この結果を永続化できない場合は`:persistence_failed`で停止する。永続ペイロードの準備・保存再試行・取得先除外を実行後に残さない。後の明示的な収集は新しい観測であり、前回ダウンロードの復旧ではない。[ADR 0013](../adr/0013-retire-interrupted-storage-recovery.md)を参照する。

各確認記録の `metadata` は取得先ID、対象ID、登録一覧URLを保持する。PDF確認は一覧確認ID、一覧応答の最終URL、観測したhref、解決済み資料URL、リンク文字列、見出しも保持する。一覧確認は応答の最終URLを保持する。設定変更や無効化でこれらの記録を書き換えない。受理PDFでは、オブジェクト通信前にHTTP観測情報を検証し、条件付き保存とサイズ・SHA-256の検証が完了するまでバイト列をメモリ上だけで保持する。その後、不変のRustFS参照を持つ原本・取得・変更不可のHTTP確認を同時に確定する。DBコミット失敗では実行を停止し、RustFSに参照されない変更不可のオブジェクトが残る場合があるが、整理のために削除しない。後の同一内容の条件付き書込では検証して再利用する。プロセス終了では、完了した取得を作らずメモリ上の観測情報を失う可能性がある。成功PDF確認は、短信識別を持たない取得記録から、不変でバイト単位の重複を排除した原本を参照する。再実行は別の確認・取得試行を作るが、同一バイト列は原本を再利用する。リクエスト開始後のPDF失敗は失敗取得記録を保持し、304応答と送信前の失敗は取得記録を捏造しない。

収集は抽出・分類・運用者による採用を呼び出さない。[上限付きの価値検証手順](earnings-value-validation.md)で取得原本と検索結果を確認する。

## 確認済みの新着 PDF を通知用 RSS に載せる

検証には現行スキーマの独立した DB と RustFS バケットを使う。取得先を指定する人が、
一覧、公開元の条件、PDF の URL、リリースの公開時期を確認する。実際の識別子・URL・
証跡は非公開の運用記録に置く。有効な登録済み取得先 ID と、その一覧に掲載された
解決済み PDF の完全な URL をクエリ文字列も含めて位置引数として渡す。両方のリクエストに
確認済みの最終 URL を使い、開始時刻を UTC で記録する。この実行では DB と HTTP の依存アプリ
だけを起動し、定期取り込みは開始しない。

```sh
mix lens.earnings.collect SOURCE_ID 'https://publisher.invalid/selected.pdf?edition=2'
```

リンクが1つだけ一致することを要求する。一致なし、曖昧な一致、一覧を読み取れない場合、
実行上限への到達、HTTP リクエストの失敗で停止する。リダイレクトでも停止する。
遷移先を確認してから登録一覧を更新するか、一覧に掲載された別の PDF URL を指定する。
コマンドは収集前に取得先 ID と URL の形式を検証し、保存した確認記録の ID と結果を返す。
収集が停止した場合はエラーで終了する。`Collector.run_selected/3` を使う呼び出し側は、
両方のリクエストに適用する `allowed_url?` ポリシーも指定できる。結果は非公開で確認し、
指定 URL の PDF 取得成功を確認してから先へ進む。中断後は
`earnings_http_checks` を `metadata` の取得先 ID と実行時間帯で調べる。PDF 確認記録の
`acquisition_id` で `earnings_acquisitions` の行を確認する。PDF 確認記録がない場合は、
取得履歴を発行元、完全な URL、実行時間帯で調べ、保存失敗の有無を確認する。取得成功記録から
再開する前に保存原本を検証する。オブジェクト保存後に DB のコミットが失敗した場合は上記の
保存障害時の手順に従う。

[価値検証手順](earnings-value-validation.md) と同様に、成功した PDF 確認記録の取得行 ID
から保存原本 ID と出典用取得 ID を確認する。保存原本を取得して対象リリースと照合する。
`mix lens.earnings.extract --original ORIGINAL_ID` で抽出して本文を確認し、出典用取得 ID と
PDF が裏付ける識別情報を `Lens.Earnings.confirm_identity/2` に渡す。原本を取得できない
場合、抽出が失敗した場合、識別が確定できない場合は停止する。[通知用 RSS](earnings-feed.md)
を読み、対象項目、全文、原本リンク、繰り返し読み取ったときの GUID を確認する。

収集を再実行すると PDF を再要求し、新しい取得試行を記録する。バイト列が同じなら保存原本を
再利用する。同じ DB で同じリリース識別を確定すると UUID と RSS GUID を再利用する。
後続手順が中断した場合、保存原本と出典を確認できる取得成功記録から再開する。リリース記録と
通知側の履歴を保持する。合成データによる検証は隔離環境での手順を確認する。本番配信と
次回巡回での再送なしは別途運用受け入れで確認する。

</details>
