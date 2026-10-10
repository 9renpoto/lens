---
status: accepted
---

# Record file storage work before saving the PDF

If Lens uses a separate file storage service, save a work record in the database before writing the PDF. Record its acquisition source, intended storage location and the information needed to identify the acquired PDF. Do not start the storage write if the work record cannot be saved.

Memory-only work tracking disappears when the application restarts. A database work record lets recovery find unfinished work after restart, check whether the PDF was saved and complete its corresponding acquisition record. Treat storage as complete only when both the PDF and its record are available. When the PDF is already saved, reuse it instead of downloading it again from the publisher.

Allow automatic recovery with a finite retry count and manual recovery by the operator. Repeating recovery must not duplicate records or overwrite saved PDFs. When automatic retries reach their limit, retain the unfinished work for operator attention. Allow one initial attempt and at most three automatic retries, eligible 1 minute, 5 minutes and 30 minutes after the preceding failure. Consume the persisted attempt budget before object I/O. Authentication, configuration and integrity failures require operator attention. An operator may schedule one additional audited attempt without resetting the automatic budget.

This protocol recovers interrupted writes, not loss or inconsistency after restoring backups. For the latter, restore PostgreSQL and RustFS as a coordinated pair and verify completed object references and content hashes under [the RustFS storage decision](0005-store-pdfs-in-rustfs.md). If a valid object cannot be restored, keep it explicitly unavailable for operator recovery. The recovery foundation below implements interrupted-write recovery; collection activation, migration and coordinated restore remain separate tasks.

## Durable recovery foundation (#144)

Each verified RustFS location retains its endpoint and bucket as immutable destination facts. Reads require the configured or explicitly supplied client to match both fields; a mismatch returns `destination_mismatch` before object I/O. Restoring PostgreSQL bytes requires both the recorded size and SHA-256 to match, enforced by the database immutability trigger.

A conflicting immutable location immediately places the work in `attention`, retaining the payload and releasing the lease. It does not consume further automatic attempts; an operator retry records the failed outcome in its audit.

The schema downgrade acquires the matching exclusive transaction lock before inspecting originals and retains it through the DDL commit. It refuses removal while any RustFS-only original remains.

`Lens.Earnings.StorageWork.prepare/2` commits provenance, normalized release identity (if present), endpoint, bucket, content-derived key, SHA-256, byte size and accepted bytes to `earnings_storage_work`. Reusing an acquisition ID requires identical facts, including compatibility with any existing successful acquisition; an existing failure or conflicting observation is rejected before object I/O. Preparation and recovery reject an enclosing repository transaction so object I/O cannot precede the preparation commit. Preparation performs no object I/O.

`claim/2` uses a row lock to persist the attempt count, a unique lease token and a 120-second expiry before returning. Each RustFS request is bounded to at most 30 seconds; checking, creating and verifying require at most three requests (90 seconds). No database transaction remains open during object I/O. Completion checks both the token and expiry under a row lock, so an expired or replaced worker cannot complete. A discovered expired lease counts as a failed consumed attempt; its retry delay starts at lease expiry. Restarting never resets the budget.

`recover/3` verifies the existing object first, creates from retained bytes only when absent, and atomically commits the successful acquisition together with `completed` state and deletion of the work payload. An interrupted completion transaction retains the payload; an acquisition conflict discovered at completion rolls back that transaction and records operator attention while retaining the payload. Authentication, configuration, integrity and permanent HTTP rejection failures become `attention`; transient failures become `pending` with a persisted eligibility time, then `exhausted` after attempt four. Ambiguous write results follow the same bounded recovery path. Recovery never downloads from the publisher or overwrites an object.

`manual_retry/3` accepts a nonempty operator identifier (at most 200 bytes) only for `attention` or `exhausted` work. It commits one queued audit and one pending manual attempt under the same lock. A manual attempt increments a separate counter, records success, failure or lease expiry in `earnings_storage_retry_audits`, and never automatically repeats. `unfinished/2` returns pages of at most 100 metadata rows without payloads, using a limit and offset; `audit/1` exposes manual attempt history. These are trusted application/operator functions; the authenticated operator HTTP interface remains #73.

The supervised `Lens.Earnings.StorageRecovery` poller is disabled by default. Set `LENS_STORAGE_RECOVERY_ENABLED=true` to discover eligible and expired work from PostgreSQL every second, processing one item per poll. `false` explicitly disables it; any other value fails startup with a generic configuration error. No in-memory queue is required after restart. Operators can use `Lens.Earnings.RustFS.new/0` and `StorageWork.recover_due/1` for a bounded batch, or schedule an audited retry with `StorageWork.manual_retry/3`. Changing the configured destination does not redirect prepared work: recovery requires its original endpoint and bucket, and a mismatch moves pending work to operator attention without consuming an attempt.

Collection does not yet call preparation. When `StorageWork.recover/3` completes, it passes the verified RustFS reference to acquisition persistence in the same transaction that marks the work complete. New RustFS-only originals have `bytes = NULL`; an existing original with the same content keeps its PostgreSQL copy. Reads use the selected original location and do not fall back between backends. Connecting collection to preparation remains #146; migrating retained PostgreSQL originals is #145. This stage does not remove PostgreSQL copies or establish the coordinated restore guarantee in #147.

CI runs `test/system/earnings_storage_recovery_check.exs` against real PostgreSQL and pinned RustFS in an isolated database and a random bucket. It verifies committed preparation after worker death, saved-object reuse after completion rollback, concurrent preparation with conflicting provenance, concurrent claims and concurrent audited retry requests. Use disposable storage for this check; it retains fixtures and buckets for inspection.

<details>
<summary>日本語</summary>

検証済みのRustFS保存先にはendpointとbucketを変更不可の接続先情報として保存する。読取時は設定済みまたは明示的に渡したクライアントが両項目と一致する必要があり、不一致ならオブジェクトI/O前に`destination_mismatch`を返す。PostgreSQLバイト列の復元は、記録済みサイズとSHA-256の両方が一致する場合だけ許可し、DBの不変性トリガーで強制する。

変更不可の保存先が競合する場合、payloadを保持しリースを解除して、作業を即座に`attention`へ遷移させる。その後の自動試行予算は消費せず、運用者が再試行した場合は失敗結果を監査記録に残す。

スキーマのダウングレードでは原本の確認前に対応する排他トランザクションロックを取得し、DDLのcommitまで保持する。RustFS専用原本が残っている場合は削除を拒否する。

# PDFを保存する前に保存作業を記録する

Lensで独立したファイル保存サービスを使う場合、PDFを書き込む前にデータベースへ作業記録を残す。取得元・予定する保存先・取得したPDFを識別するための情報を記録する。作業記録を保存できない場合は、ストレージへの書き込みを始めない。

メモリだけで作業を管理すると、アプリの再起動でその情報が消える。データベースに作業記録を残すことで、再起動後に未完了の作業を見つけ、PDFが保存済みか確認し、対応する取得記録を完成させられる。PDFと対応する記録が両方揃ってから保存完了と扱う。PDFが保存済みの場合は、公開元から取り直さず再利用する。

自動復旧は再試行回数を制限し、運用者による手動復旧も可能にする。繰り返しても記録の重複や保存済みPDFの上書きを起こさない。自動再試行が上限に達した場合は、未完了の作業を残して運用者の対応を待つ。初回に加えて自動再試行を最大3回とし、直前の失敗から1分・5分・30分後に実行可能とする。オブジェクト通信前に試行予算を永続的に消費する。認証・設定・整合性の失敗は運用者の対応を待つ。運用者は、自動試行の予算をリセットせず、監査記録付きの追加試行を1回予約できる。

この方式が復旧するのは中断した書き込みであり、バックアップ復元後のファイル欠落や不整合ではない。後者は[RustFSへの保存方針](0005-store-pdfs-in-rustfs.md)に従い、PostgreSQLとRustFSを揃えて復元した後、完了済みオブジェクトの参照先と内容ハッシュを検証する。有効なファイルを復元できない場合は、運用者が復旧するまで利用不可として明示する。永続的な作業管理は増えるが、メモリに頼らず中断した保存処理を復旧できるようになる。以下の復旧基盤で中断した書き込みの復旧を実装する。収集への接続・移行・両保存先の復元は別タスクとする。

## 永続的な復旧基盤（#144）

`Lens.Earnings.StorageWork.prepare/2`は、取得経緯・正規化した開示識別情報（ある場合）・endpoint・bucket・内容由来のキー・SHA-256・サイズ・受理したバイト列を`earnings_storage_work`へコミットする。取得IDを再利用する場合は、既存の取得成功記録との整合も含めて事実がすべて一致しなければならない。既存の失敗記録や競合する取得記録はオブジェクト通信前に拒否する。準備と復旧は外側のリポジトリトランザクション内では拒否し、準備のコミット前にオブジェクト通信が始まらないようにする。準備ではオブジェクト通信を行わない。

`claim/2`は行ロックを使い、試行回数・一意なリーストークン・120秒後の期限を永続化してから返す。RustFSの各リクエストは最大30秒に制限され、確認・作成・検証の最大3リクエストは90秒以内となる。オブジェクト通信中はDBトランザクションを開いたままにしない。完了時に行ロックの下でトークンと期限を検査し、期限切れや交代済みのワーカーが完了できないようにする。検出した期限切れリースは消費済み試行の失敗と扱い、再試行の待機時間はリース期限から数える。再起動しても予算はリセットしない。

`recover/3`は既存オブジェクトを先に検証し、存在しない場合だけ保持したバイト列から作成する。取得成功の記録・`completed`状態・作業ペイロードの削除を同じトランザクションでコミットする。完了トランザクションが中断された場合はペイロードを保持する。完了時に取得記録の競合が発覚した場合はトランザクションをロールバックし、ペイロードを保持したまま要対応状態を記録する。認証・設定・整合性・恒久的なHTTP拒否の失敗は`attention`、一時的な失敗は実行可能時刻を永続化した`pending`となり、4回目の試行後は`exhausted`となる。書き込み結果が不明な場合も同じ上限付きの復旧を行う。復旧では公開元から取得し直さず、オブジェクトを上書きしない。

`manual_retry/3`は`attention`または`exhausted`の作業に対し、空でない最大200バイトの運用者識別子を受け付ける。同じ行ロックの下で、予約監査記録と1回分の手動試行をコミットする。手動試行は別カウンターを増やし、成功・失敗・リース期限切れを`earnings_storage_retry_audits`へ記録し、自動では繰り返さない。`unfinished/2`は件数上限とoffsetでページを指定し、ペイロードを除くメタデータを最大100件返し、`audit/1`は手動試行履歴を公開する。これらは信頼されたアプリケーション・運用者向け関数であり、認証付き運用者HTTPインターフェースは#73で扱う。

監督下の`Lens.Earnings.StorageRecovery`ポーラーは初期状態で無効。`LENS_STORAGE_RECOVERY_ENABLED=true`で、PostgreSQLから実行可能・期限切れの作業を1秒ごとに検出し、各ポーリングで1件処理する。`false`は明示的に無効化し、その他の値は一般的な設定エラーで起動を失敗させる。再起動後にメモリ内キューは必要ない。運用者は`Lens.Earnings.RustFS.new/0`と`StorageWork.recover_due/1`で上限付きバッチを実行でき、`StorageWork.manual_retry/3`で監査付き再試行を予約できる。設定した保存先を変えても準備済み作業を別の場所には送らず、元のendpoint・bucketとの一致を復旧の条件とする。不一致の場合、待機中の作業を試行予算を消費せずに要対応状態にする。

収集処理はまだ準備処理を呼び出さない。`StorageWork.recover/3`の完了時は、検証済みRustFS参照を取得記録の保存へ渡し、作業完了と同じトランザクションで確定する。新規のRustFS専用原本は`bytes = NULL`とし、同じ内容の既存原本があればPostgreSQLコピーを保持する。読取では原本ごとに選ばれた保存先を使い、別バックエンドへフォールバックしない。収集処理を準備へ接続する作業は#146、既存PostgreSQL原本の移行は#145で扱う。この段階ではPostgreSQLコピーを削除せず、#147の両保存先を揃えた復元保証も確立しない。

CIでは`test/system/earnings_storage_recovery_check.exs`を、実PostgreSQL・固定したRustFS・隔離DB・ランダムなbucketで実行する。ワーカー終了後の準備記録の保持、完了ロールバック後の保存済みオブジェクト再利用、異なる取得経緯での同時準備、同時取得、同時監査付き再試行予約を検証する。この検証には使い捨ての保存先を使う。検査用のfixtureとbucketは残す。

</details>
