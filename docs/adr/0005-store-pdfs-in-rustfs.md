---
status: accepted
---

# Store PDFs in RustFS

Use RustFS to store and retrieve earnings PDFs. Keep acquisition records, document identity and extracted text in PostgreSQL. The aim is to simplify Lens by delegating file storage to a dedicated service. Judge that simplification across the whole operation, including backup and recovery, rather than by Lens code size alone.

Keep identical PDF contents only once and retain changed contents as separate files. Give each file a stable location based on its contents; do not overwrite one location and rely on storage version history to identify the PDF used. Lens still determines which company and reporting period a document belongs to and which extracted text is used for search.

Keeping PDFs in PostgreSQL would allow files and their records to be backed up together without another service. We instead accept operating RustFS and coordinating file and record recovery in order to delegate file storage. Back up and restore PostgreSQL and RustFS as one recovery point. After restoration, reconcile every completed database reference against the RustFS object key and content hash. Repair a missing or mismatched object from the coordinated backup when possible; if no valid copy exists, mark the original unavailable and surface it for operator recovery. Never treat the release as complete or silently serve a different PDF. This protects against inconsistent restores that ordinary interrupted-write recovery cannot detect. Follow [ADR 0006](0006-record-file-storage-work-before-writing.md) for interrupted writes.

Consider migration to another compatible storage service only when a need arises. Do not build support for multiple storage products in this release.

## Original locations and deployment scope (#145)

Keep original identity and acquisition/extraction history in PostgreSQL. Record verified physical copies in append-only `earnings_original_storage_locations` and select an active read location in `earnings_original_read_locations`. Rows without a selection continue to read from PostgreSQL. RustFS reads require the recorded endpoint and bucket to match the client, verify size and SHA-256, and surface failures without falling back to another backend. Storage completion leaves new RustFS-only originals with `bytes = NULL` and retains any existing PostgreSQL copy. Connecting collection to preparation remains #146.

The current k3s deployment has no stored PDFs, as confirmed for this scope decision on 2026-10-10. Do not add PDF-copy batches, migration or rollback CLIs, PostgreSQL copy-back, durable rollback controls, or write fences for backend rollback. Reconsider backend migration only when a concrete need arises. PR #151 is withdrawn; the storage-location foundation from #150 remains.

Apply schema changes through forward Ecto migrations and the existing release migration hook. Preserve applied migrations; a follow-up migration removes the rollback control table and restores strict original immutability, including rejection of `NULL`-to-bytes updates. This cleanup migration is forward-only. Stop application writers before applying it; this is not a rolling deployment procedure. Recover from deployment problems using coordinated PostgreSQL and RustFS backups, rather than copying RustFS originals into PostgreSQL. For the currently empty deployment, recreating the database is acceptable; this does not authorize discarding future stored data. Coordinated restore implementation and verification remain #147. This decision does not claim deployment or restore completion.

## Retrieval and extraction boundary (#146)

Retrieve and verify the retained original's size and SHA-256 before creating an extraction attempt. If the original cannot be retrieved or fails verification, report its unavailability through a dedicated API error; the CLI identifies the requested original and the failure reason. A storage failure does not create an extraction attempt or become an extractor failure. Retrieve the requested original version without publisher access and preserve original identities and existing extraction history.

Start verification of this integration with the existing `lens-earnings-extract --original UUID` operation, processing one explicitly selected original at a time. Completing or recovering storage does not automatically start extraction in this initial stage. This keeps the change small enough to implement and exercise promptly, at the cost of a manual extraction step after storage completion. Automation remains the goal, but neither an immediate extraction hook nor a periodic scan of unextracted originals is selected for this stage. The existing regeneration operation retains its scope.

These are agreed boundaries for #146, not a claim that retrieval or extraction has switched to RustFS. Exact endpoint names, HTTP status codes and response schemas belong to the implementation contract coordinated with #73.

## Storage client foundation (#143)

`Lens.Earnings.RustFS.new/0` reads runtime configuration; `new/1` accepts explicit options. `put/2` accepts nonempty raw bytes up to 20 MiB and returns a reference containing `key`, `sha256` and `byte_size`. The key is `earnings/originals/sha256/<lowercase-sha256>.pdf`. `get/2` accepts that reference and returns the exact bytes only after checking size and SHA-256. This client has no database writes, publisher access, automatic retries or redirects. Existing acquisition and extraction remain PostgreSQL-backed until #146 connects the durable preparation and recovery protocol in [ADR 0006](0006-record-file-storage-work-before-writing.md).

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

CI runs `mix run --no-start test/system/rustfs_storage_check.exs` against RustFS `1.0.1` pinned to image digest `sha256:1803faef57627e2d9c2e7d89d655d712ddded5389040054987163043fecb6a3c`. It creates disposable test buckets using test-only credentials, proves simultaneous conditional creates preserve one winner, and checks reuse, changed contents, corrupt/missing objects and the size boundary. Run this script only against an isolated test service; it intentionally seeds corrupt objects and leaves evidence in its test buckets. Revalidate conditional creation before changing the RustFS version. This evidence establishes the client foundation, not local k3s deployment, coordinated restore (#147).

<details>
<summary>日本語</summary>

# PDFをRustFSに保存する

決算短信PDFの保存・取得にはRustFSを使う。取得記録、資料の識別情報、読み取った文章はPostgreSQLに残す。ファイルの保存を専用サービスに任せ、Lensの処理を簡単にすることが目的。Lensのコード量だけでなく、バックアップ・復旧を含む運用全体の簡単さで評価する。

同じ内容のPDFは一つだけ保存し、変更された内容は別のファイルとして残す。各ファイルには内容に基づく固定の保存場所を与える。一つの場所へ上書きしてストレージの版履歴に頼り、使用したPDFを識別する方法は取らない。どの企業・決算の資料か、検索にどの抽出本文を使うかはLensが判断する。

PDFをPostgreSQLに残せば、別のサービスを運用せずファイルと記録をまとめてバックアップできる。今回はファイル保存を任せるため、RustFSの運用と、ファイル・記録を揃えて復旧する責任を引き受ける。PostgreSQLとRustFSは一つの復旧時点としてバックアップ・復元する。復元後は、DB上の完了済み記録を一件ずつRustFSのオブジェクトキーと内容ハッシュに照合する。欠落・不一致のファイルは、可能なら同じ復旧用バックアップから修復する。有効なコピーがなければ原本を利用不可として運用者に示し、処理完了として扱ったり、別のPDFを黙って返したりしない。これは通常の中断書き込み復旧では検出できない、整合しない復元から守るためである。中断書き込みには[ADR 0006](0006-record-file-storage-work-before-writing.md)を適用し、保存前に作業記録を残し、回数を制限した自動復旧と手動復旧に対応する。

他の互換ストレージへの移行は、必要になった時点で検討する。今回のリリースでは複数製品への対応を作り込まない。

## 原本の保存先と配備範囲（#145）

原本の識別情報と取得・抽出の履歴はPostgreSQLに残す。検証済みの物理コピーは追記専用の`earnings_original_storage_locations`に記録し、`earnings_original_read_locations`で有効な読取先を選ぶ。選択記録がない行は引き続きPostgreSQLから読む。RustFSの読取では記録済みendpoint・bucketとクライアントの一致を確認し、サイズ・SHA-256を検証する。失敗時は別バックエンドへフォールバックせずエラーを返す。保存完了時、新規RustFS専用原本の`bytes`は`NULL`とし、既存PostgreSQLコピーがあれば保持する。収集処理を準備処理へ接続する作業は#146で扱う。

今回の範囲判断にあたり、2026-10-10時点のk3s配備には保存済みPDFがないことを確認した。PDFコピーのバッチ、移行・逆移行CLI、PostgreSQLへのコピー戻し、逆移行状態の永続管理、バックエンド逆移行の書込フェンスは追加しない。保存先移行は具体的な必要が生じた時点で再検討する。PR #151は取り下げ、#150の保存先記録基盤は維持する。

スキーマ変更は前方Ecto migrationと既存のリリースmigration hookで適用する。適用済みmigrationは保持し、追加migrationで逆移行制御テーブルを削除し、`NULL`からバイト列への更新も拒否する厳密な原本不変性を復元する。この整理migrationは前方適用のみとする。適用前にアプリのwriterを停止し、ローリング配備手順としては扱わない。配備問題からの復旧はRustFS原本をPostgreSQLへコピーする方式ではなく、PostgreSQLとRustFSを揃えたバックアップ復元とする。現在の空の配備ではDB再作成を許容するが、今後保存するデータの破棄を許可するものではない。両保存先を揃えた復元の実装・検証は#147で扱う。この判断は配備・復元の完了を意味しない。

## 原本取得と抽出の境界（#146）

抽出試行を作成する前に、保持した原本を取得し、サイズとSHA-256を検証する。原本を取得できない場合や検証に失敗した場合、APIは専用エラーで利用不可を示し、CLIは指定した原本と失敗理由を表示する。保存の障害では抽出試行を作らず、抽出器の失敗としても記録しない。公開元へアクセスせず指定した原本の版を取得し、原本の識別情報と既存の抽出履歴を保持する。

この接続の初期検証では、既存の`lens-earnings-extract --original UUID`操作を使い、明示的に指定した原本を1件ずつ処理する。初期段階では、保存完了や保存復旧を契機に抽出を自動開始しない。早く実装して実際に試せる規模に抑えるため、保存完了後の抽出には手動操作が必要となる。自動化は引き続き目標とするが、この段階では即時抽出のフックも未抽出原本の定期スキャンも選定しない。既存の再生成操作の対象範囲を維持する。

これは#146の合意した境界であり、原本取得や抽出がRustFSへ切り替わったことを示さない。具体的なエンドポイント名・HTTPステータスコード・応答スキーマは、#73と調整する実装契約で定める。

## 保存クライアント基盤（#143）

`Lens.Earnings.RustFS.new/0`は実行時設定を読み、`new/1`は明示的な設定を受け取る。`put/2`は空でない20 MiB以下の生バイト列を受け取り、`key`・`sha256`・`byte_size`を含む参照を返す。キーは`earnings/originals/sha256/<lowercase-sha256>.pdf`。`get/2`はこの参照を受け取り、サイズ・SHA-256を照合してから正確なバイト列を返す。このクライアントはDB書込・公開元へのアクセス・自動再試行・リダイレクトを行わない。#146で[ADR 0006](0006-record-file-storage-work-before-writing.md)の永続的な準備・復旧プロトコルへ接続するまで、既存の取得・抽出はPostgreSQLを使う。

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

CIでは`mix run --no-start test/system/rustfs_storage_check.exs`を、イメージダイジェスト`sha256:1803faef57627e2d9c2e7d89d655d712ddded5389040054987163043fecb6a3c`で固定したRustFS `1.0.1`に対して実行する。テスト専用認証情報で使い捨てバケットを作り、同時条件付き作成で成功した1件が維持されること、再利用・内容変更・破損と欠落・サイズ境界を検証する。このスクリプトは隔離したテストサービスでのみ実行する。意図的に破損オブジェクトを作り、テストバケットに検証結果を残す。RustFSのバージョン変更前には条件付き作成を再検証する。この証跡はクライアント基盤の確認であり、ローカルk3s配置・両保存先の復元（#147）の完了ではない。

</details>
