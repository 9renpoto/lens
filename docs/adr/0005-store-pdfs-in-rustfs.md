---
status: accepted
---

# Store PDFs in RustFS

Use RustFS to store and retrieve earnings PDFs. Keep acquisition records, document identity and extracted text in PostgreSQL. The aim is to simplify Lens by delegating file storage to a dedicated service. Judge that simplification across the whole operation, including backup and recovery, rather than by Lens code size alone.

Keep identical PDF contents only once and retain changed contents as separate files. Give each file a stable location based on its contents; do not overwrite one location and rely on storage version history to identify the PDF used. Lens still determines which company and reporting period a document belongs to and which extracted text is used for search.

Keeping PDFs in PostgreSQL would allow files and their records to be backed up together without another service. We instead accept operating RustFS and coordinating file and record recovery in order to delegate file storage. Back up and restore PostgreSQL and RustFS as one recovery point. After restoration, reconcile every completed database reference against the RustFS object key and content hash. Repair a missing or mismatched object from the coordinated backup when possible; if no valid copy exists, mark the original unavailable and surface it for operator recovery. Never treat the release as complete or silently serve a different PDF. This protects against inconsistent restores that ordinary interrupted-write recovery cannot detect. Follow [ADR 0006](0006-record-file-storage-work-before-writing.md) for interrupted writes.

Consider migration to another compatible storage service only when a need arises. Do not build support for multiple storage products in this release.

## Original locations and rollback (#145)

Keep original identity and acquisition/extraction history in PostgreSQL. Record each verified physical copy in the append-only `earnings_original_storage_locations` table and select one active read location per original in `earnings_original_read_locations`. Legacy rows without a selection continue to read from PostgreSQL. Reads follow the selected backend exactly; a RustFS read failure is returned and never falls back to PostgreSQL.

`Lens.Earnings.StorageMigration.migrate_batch/2` processes at most 100 UUID-ordered originals per call. It verifies the retained PostgreSQL bytes, writes and retrieves the RustFS object, and changes the active read location only after exact-byte, size and SHA-256 verification. It keeps PostgreSQL copies and returns per-original failures to the caller. When a batch has failures, `next_after` stops immediately before the earliest failed UUID, so callers can resume without skipping failed rows; already migrated rows are safely skipped when retried.

`mix lens.earnings.storage.rollback` performs an explicit bounded rollback. A durable database flag and PostgreSQL advisory lock fence original writes while rollback is active. Existing PostgreSQL copies are reverified before selection; RustFS-only originals are fetched, verified and hydrated into `bytes` once. The fence remains active across incomplete batches and process restarts, and clears only after no original reads from RustFS. If a batch has failures, its `next_after` stops before the earliest failed UUID for safe resumption. Keep both location records and PostgreSQL copies; deletion and retention duration require a separately agreed cleanup.

The forward Ecto migration adds the location and control tables and permits a one-time `NULL`-to-bytes restoration for RustFS-only originals. Deploy it through the existing release migration hook. A separate PDF-copy Mix task or Kubernetes Job is not required for the current deployment when its pre-deploy inventory confirms there are no PostgreSQL originals to copy.

This is a storage decision, not a claim that a deployment has completed or that retained PostgreSQL originals have been copied.

## Storage client foundation (#143)

`Lens.Earnings.RustFS.new/0` reads runtime configuration; `new/1` accepts explicit options. `put/2` accepts nonempty raw bytes up to 20 MiB and returns a reference containing `key`, `sha256` and `byte_size`. The key is `earnings/originals/sha256/<lowercase-sha256>.pdf`. `get/2` accepts that reference and returns the exact bytes only after checking size and SHA-256. This client has no database writes, publisher access, automatic retries or redirects. `StorageWork.recover/3` passes its verified object reference into acquisition completion, which records a RustFS read location and leaves new RustFS-only originals with `bytes = NULL`. Acquisition preparation is not yet connected to collection; that remains #146.

Writes use signed S3 requests with `If-None-Match: *`, never a check followed by an unconditional write. Successful creates and existing-object responses (`412`) both require retrieval and byte verification before returning success. A concurrent conflict (`409`) remains explicit for the recovery layer. Missing objects return `:not_found`; mismatched or encoded bytes return `:integrity_error`; authentication failures return `:unauthorized`; service failures return `:unavailable`. Transport failures and total request timeouts are explicit. Error bodies and credentials are not included in results or client inspection. Actual streamed bytes are bounded by the reference size; ETags do not establish integrity.

| Environment variable | Meaning |
| --- | --- |
| `LENS_RUSTFS_ENDPOINT` | Absolute HTTP(S) origin, including an optional port; no credentials, path, query or fragment. Use HTTPS outside an isolated trusted network |
| `LENS_RUSTFS_BUCKET` | Existing bucket, 3–63 lowercase letters/digits/hyphens, beginning and ending with a letter/digit |
| `LENS_RUSTFS_ACCESS_KEY_ID` | Access key from runtime secrets |
| `LENS_RUSTFS_SECRET_ACCESS_KEY` | Secret key from runtime secrets |
| `LENS_RUSTFS_REGION` | Signing region; defaults to `us-east-1` |
| `LENS_RUSTFS_TIMEOUT_MS` | Per-request wall-clock bound, 1–30000 ms; defaults to 30000. A write and its verification use separate requests |

Leave all variables unset to keep storage unconfigured. Partial configuration or an invalid timeout fails runtime configuration without printing secret values; the constructor validates the origin, bucket and credentials before requests. Provision the bucket separately and grant the application only object read/write access in the originals prefix. The client does not create buckets, delete objects or supply production credentials.

CI runs `mix run --no-start test/system/rustfs_storage_check.exs` against RustFS `1.0.1` pinned to image digest `sha256:1803faef57627e2d9c2e7d89d655d712ddded5389040054987163043fecb6a3c`. It creates disposable test buckets using test-only credentials, proves simultaneous conditional creates preserve one winner, and checks reuse, changed contents, corrupt/missing objects and the size boundary. Run this script only against an isolated test service; it intentionally seeds corrupt objects and leaves evidence in its test buckets. Revalidate conditional creation before changing the RustFS version. This evidence establishes the client foundation, not local k3s deployment, retained-original migration or coordinated restore (#145/#147).

<details>
<summary>日本語</summary>

# PDFをRustFSに保存する

決算短信PDFの保存・取得にはRustFSを使う。取得記録、資料の識別情報、読み取った文章はPostgreSQLに残す。ファイルの保存を専用サービスに任せ、Lensの処理を簡単にすることが目的。Lensのコード量だけでなく、バックアップ・復旧を含む運用全体の簡単さで評価する。

同じ内容のPDFは一つだけ保存し、変更された内容は別のファイルとして残す。各ファイルには内容に基づく固定の保存場所を与える。一つの場所へ上書きしてストレージの版履歴に頼り、使用したPDFを識別する方法は取らない。どの企業・決算の資料か、検索にどの抽出本文を使うかはLensが判断する。

PDFをPostgreSQLに残せば、別のサービスを運用せずファイルと記録をまとめてバックアップできる。今回はファイル保存を任せるため、RustFSの運用と、ファイル・記録を揃えて復旧する責任を引き受ける。PostgreSQLとRustFSは一つの復旧時点としてバックアップ・復元する。復元後は、DB上の完了済み記録を一件ずつRustFSのオブジェクトキーと内容ハッシュに照合する。欠落・不一致のファイルは、可能なら同じ復旧用バックアップから修復する。有効なコピーがなければ原本を利用不可として運用者に示し、処理完了として扱ったり、別のPDFを黙って返したりしない。これは通常の中断書き込み復旧では検出できない、整合しない復元から守るためである。中断書き込みには[ADR 0006](0006-record-file-storage-work-before-writing.md)を適用し、保存前に作業記録を残し、回数を制限した自動復旧と手動復旧に対応する。

他の互換ストレージへの移行は、必要になった時点で検討する。今回のリリースでは複数製品への対応を作り込まない。

## 原本の保存先とロールバック（#145）

原本の識別情報と取得・抽出の履歴はPostgreSQLに残す。検証済みの物理コピーは追記専用の`earnings_original_storage_locations`テーブルに記録し、原本ごとの有効な読取先を`earnings_original_read_locations`で選ぶ。選択記録がない既存行は引き続きPostgreSQLから読む。読取は選択された保存先だけを使い、RustFSの読取失敗時にPostgreSQLへ黙って切り替えない。

`Lens.Earnings.StorageMigration.migrate_batch/2`は、呼び出しごとにUUID順で最大100件を処理する。PostgreSQLに保持したバイト列を検証し、RustFSへ書き込んで再取得し、バイト列・サイズ・SHA-256が完全一致した後にだけ有効な読取先を切り替える。PostgreSQLコピーは保持し、原本ごとの失敗を呼び出し元へ返す。バッチに失敗がある場合、`next_after`は最も早い失敗UUIDの直前で止まるため、失敗行を飛ばさず再開できる。再試行時に移行済みの行は安全にスキップする。

`mix lens.earnings.storage.rollback`で明示的な上限付きロールバックを実行する。DBの永続フラグとPostgreSQL advisory lockで、ロールバック中の原本書込をフェンスする。既存PostgreSQLコピーは再検証してから選択する。RustFS専用原本は取得・検証し、`bytes`へ一度だけ復元する。未完了バッチやプロセス再起動後もフェンスを維持し、RustFSを読む原本がなくなった場合だけ解除する。バッチに失敗がある場合、`next_after`は最も早い失敗UUIDの直前で止まり、安全に再開できる。保存先記録とPostgreSQLコピーを保持し、削除や保持期間は別途合意する整理作業で扱う。

前方Ecto migrationで保存先・制御テーブルを追加し、RustFS専用原本を一度だけ`NULL`からバイト列へ復元できるようにする。既存のリリースmigration hookで適用する。現在の配備前件数確認でコピー対象のPostgreSQL原本がない場合、PDFコピー専用Mix taskやKubernetes Jobは追加しない。

これは保存先の判断であり、配備完了やPostgreSQL原本のコピー完了を意味しない。

## 保存クライアント基盤（#143）

`Lens.Earnings.RustFS.new/0`は実行時設定を読み、`new/1`は明示的な設定を受け取る。`put/2`は空でない20 MiB以下の生バイト列を受け取り、`key`・`sha256`・`byte_size`を含む参照を返す。キーは`earnings/originals/sha256/<lowercase-sha256>.pdf`。`get/2`はこの参照を受け取り、サイズ・SHA-256を照合してから正確なバイト列を返す。このクライアントはDB書込・公開元へのアクセス・自動再試行・リダイレクトを行わない。`StorageWork.recover/3`は検証済みオブジェクト参照を取得完了処理へ渡し、RustFSの読取先を記録する。新しいRustFS専用原本の`bytes`は`NULL`にする。取得準備はまだ収集処理に接続しておらず、#146で扱う。

書込は署名付きS3リクエストと`If-None-Match: *`を使い、存在確認後の無条件書込にはしない。新規作成成功・既存オブジェクトの応答（`412`）のどちらも、取得・バイト検証後に成功を返す。同時書込の競合（`409`）は復旧層へ明示する。欠落は`:not_found`、バイト不一致・エンコードされた内容は`:integrity_error`、認証失敗は`:unauthorized`、サービス障害は`:unavailable`を返す。通信失敗・リクエスト全体のタイムアウトも明示する。エラー本文・認証情報は結果やクライアントの表示に含めない。実際のストリームバイト列を参照サイズで制限し、ETagを整合性の根拠にしない。

| 環境変数 | 意味 |
| --- | --- |
| `LENS_RUSTFS_ENDPOINT` | ポート付きも許可する絶対HTTP(S)オリジン。認証情報・パス・クエリ・フラグメントは禁止。隔離した信頼済みネットワーク外ではHTTPSを使う |
| `LENS_RUSTFS_BUCKET` | 既存バケット。小文字英字・数字・ハイフンの3〜63文字で、先頭・末尾は英字か数字 |
| `LENS_RUSTFS_ACCESS_KEY_ID` | 実行時の秘密情報から取得するアクセスキー |
| `LENS_RUSTFS_SECRET_ACCESS_KEY` | 実行時の秘密情報から取得するシークレットキー |
| `LENS_RUSTFS_REGION` | 署名リージョン。既定値は`us-east-1` |
| `LENS_RUSTFS_TIMEOUT_MS` | リクエスト単位の実時間上限。1〜30000 ms、既定値30000。書込と検証は別リクエスト |

全変数が未設定なら保存を未設定に保つ。不完全な設定・不正タイムアウトは秘密の値を表示せず実行時設定を失敗させる。接続先・バケット・認証情報はコンストラクターがリクエスト前に検証する。バケットは別途用意し、アプリには原本プレフィックス内のオブジェクト読取・書込権限のみを与える。クライアントはバケット作成・オブジェクト削除・本番認証情報の提供を行わない。

CIでは`mix run --no-start test/system/rustfs_storage_check.exs`を、イメージダイジェスト`sha256:1803faef57627e2d9c2e7d89d655d712ddded5389040054987163043fecb6a3c`で固定したRustFS `1.0.1`に対して実行する。テスト専用認証情報で使い捨てバケットを作り、同時条件付き作成で成功した1件が維持されること、再利用・内容変更・破損と欠落・サイズ境界を検証する。このスクリプトは隔離したテストサービスでのみ実行する。意図的に破損オブジェクトを作り、テストバケットに検証結果を残す。RustFSのバージョン変更前には条件付き作成を再検証する。この証跡はクライアント基盤の確認であり、ローカルk3s配置・既存原本移行・両保存先の復元（#145・#147）の完了ではない。

</details>
