# Container runtime contract

Lens provides a Linux container image and an application runtime contract.
This document describes the application interface without selecting an
environment or orchestration tool. See
[ADR 0012](adr/0012-document-only-the-application-runtime-contract.md).

## Container image

Images are published to `ghcr.io/9renpoto/lens`. Use a released
`vMAJOR.MINOR.PATCH` tag for production; release tags with prerelease or build
metadata are unsupported. The release tag, `latest`, and its commit-specific
`sha-...` tag come from the same build. Image publication follows successful
CI; version preparation and tagging are described in the
[release guide](releasing.md).

The container runs as the unprivileged `lens` user, listens on
`0.0.0.0:$PORT`, and needs no writable application filesystem volume.

## Required services

- PostgreSQL 18 stores canonical records and derived search data.
- RustFS stores earnings PDFs. PostgreSQL retains their metadata and acquisition history.
- Configured feed sources must be reachable from the application.
- The unauthenticated HTTP API requires a private access boundary.

Persistent storage is required for records and originals designated for
retention. The bounded validation procedure uses explicitly disposable
development/test data under [ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md).

## Application configuration

Pass configuration through environment variables. Deliver credentials as
runtime secrets rather than committing their values.

| Variable | Requirement | Description |
| --- | --- | --- |
| `DATABASE_URL` | Required | PostgreSQL Ecto URL, for example `ecto://lens:PASSWORD@postgres.example/lens`. |
| `SECRET_KEY_BASE` | Required for the HTTP server | Unique high-entropy Phoenix secret. |
| `PHX_HOST` | Set for the serving environment | Host used to generate URLs; defaults to `localhost`. |
| `PORT` | Optional | HTTP listen port; defaults to `4000`. |
| `POOL_SIZE` | Optional | Database pool size; defaults to `10`. |

## Earnings PDF storage

Use synchronous verified saves under [ADR 0013](adr/0013-retire-interrupted-storage-recovery.md). Each original retains one immutable RustFS reference. The disposable-data scope does not establish production restore guarantees.

Earnings PDF acquisition from feeds requires a provisioned RustFS bucket and
the following settings:

| Variable | Requirement | Description |
| --- | --- | --- |
| `LENS_RUSTFS_ENDPOINT` | Required for collection and RustFS-backed reads | RustFS HTTP(S) origin. HTTPS is required outside an isolated trusted network. |
| `LENS_RUSTFS_BUCKET` | Required with endpoint | Bucket for retained originals. |
| `LENS_RUSTFS_ACCESS_KEY_ID` | Required with endpoint | Access key delivered as a secret. |
| `LENS_RUSTFS_SECRET_ACCESS_KEY` | Required with endpoint | Secret key delivered as a secret. |
| `LENS_RUSTFS_REGION` | Optional | Defaults to `us-east-1`. |
| `LENS_RUSTFS_TIMEOUT_MS` | Optional | Integer from 1 to 30000; defaults to 30000. |

If any RustFS variable is supplied, all four required values must be nonempty.
Partial configuration or an invalid timeout fails startup; the storage client
rejects other invalid configuration before use.

PostgreSQL retains identity, acquisition history, and
extraction/search data. RustFS retains new PDF bytes. Reads verify size and
SHA-256 and do not silently fall back to another backend or refetch the
publisher. A database dump does not contain RustFS-backed PDF bytes;
preservation requirements are defined in [ADR 0005](adr/0005-store-pdfs-in-rustfs.md).


Feed subscriptions use the scheduler; see the [validation procedure](reference/earnings-value-validation.md).

<a id="database-initialization"></a>

### Database preparation

Prepare the database before starting the application, using the same
image and `DATABASE_URL`:

```sh
/app/bin/lens eval 'Lens.Release.prepare()'
/app/bin/lens start
```

Run these as separate commands. Preparation initializes empty databases with
Ecto migrations. It adopts an existing database with the supported legacy
fingerprint and applies pending migrations. See [ADR 0018](adr/0018-upgrade-postgresql-with-ecto-migrations.md)
for the baseline. The initial adoption preserves the legacy records, their
constraints and the fingerprint that the previous release uses. Repeating
preparation skips migrations already recorded in `schema_migrations`.

If preparation fails, keep the previous release in service and use the error
to identify the schema or migration that blocked the upgrade. Verify the
database and release versions before retrying. A failed migration rolls back
its own changes, and earlier successful migrations remain applied. Keep the
existing database and its migration records intact while diagnosing the issue.

If the release requires a manual migration, follow the procedure for that
release. Verify a recoverable PostgreSQL backup and the corresponding RustFS
objects before changing retained records. Rehearse the procedure and verify
records and references on a restored copy. After the approved manual work,
run preparation again and start the new release only after it succeeds. Use
[ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md) when
recreating an explicitly disposable database.

Use one active application process because each process owns its feed scheduler.

| Endpoint | Meaning |
| --- | --- |
| `GET /api/health` | Process liveness; returns `200` while the web process runs. |
| `GET /api/ready` | Returns `200` when PostgreSQL accepts a query; otherwise `503`. It does not check RustFS or publisher availability. |

See [source operations](operations.md) and [search](search.md) for application
usage.

<details>
<summary>日本語</summary>

# コンテナ実行契約

LensはLinuxコンテナイメージとアプリの実行契約を提供する。
この文書は環境や配置ツールを指定せず、アプリのinterfaceを記載する。
[ADR 0012](adr/0012-document-only-the-application-runtime-contract.md)を参照する。

## コンテナイメージ

イメージは`ghcr.io/9renpoto/lens`に公開する。本番にはリリース済みの
`vMAJOR.MINOR.PATCH`タグを使い、prerelease・build metadata付きタグは対象外とする。
リリースタグ・`latest`・コミット固有の`sha-...`タグは同じbuildから作る。
CI成功後にイメージを公開する。バージョン準備とタグ作成は[リリース手順](releasing.md)を参照する。

コンテナは非特権の`lens`ユーザーで動作し、`0.0.0.0:$PORT`で待ち受ける。
書込可能なアプリ用filesystem volumeは必要ない。

## 必要なサービス

- PostgreSQL 18は正となる記録と検索用データを保存する。
- RustFSは決算PDFを保存する。PostgreSQLにはメタデータと取得履歴を保持する。
- 設定したフィード取得先へアプリから接続できる必要がある。
- 認証を持たないHTTP APIには非公開のアクセス境界が必要。

保持対象とした記録・原本には永続保存が必要。
上限付き検証では[ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md)に従い、
明示的に破棄可能な開発・テストデータを使う。

## アプリ設定

設定は環境変数で渡す。認証情報は値をコミットせず、実行時のsecretとして渡す。

| 変数 | 要件 | 説明 |
| --- | --- | --- |
| `DATABASE_URL` | 必須 | PostgreSQL Ecto URL。例：`ecto://lens:PASSWORD@postgres.example/lens`。 |
| `SECRET_KEY_BASE` | HTTP serverに必須 | 固有で高エントロピーのPhoenix secret。 |
| `PHX_HOST` | 提供環境に合わせて指定 | URL生成に使うhost。既定は`localhost`。 |
| `PORT` | 任意 | HTTP待受port。既定は`4000`。 |
| `POOL_SIZE` | 任意 | DB pool size。既定は`10`。 |

## 決算PDFの保存

[ADR 0013](adr/0013-retire-interrupted-storage-recovery.md)に従い同期的な検証済み保存を使う。各原本は一つの不変のRustFS参照を保持する。破棄可能なデータの範囲では本番復元の保証は成立しない。

決算フィード資料の取得には、用意済みのRustFSバケットと次の設定が必要。

| 変数 | 要件 | 説明 |
| --- | --- | --- |
| `LENS_RUSTFS_ENDPOINT` | 収集・RustFS保存原本の読取に必要 | RustFSのHTTP(S) origin。隔離された信頼済みネットワーク外ではHTTPSを必須とする。 |
| `LENS_RUSTFS_BUCKET` | endpointとともに必要 | 原本を保持するバケット。 |
| `LENS_RUSTFS_ACCESS_KEY_ID` | endpointとともに必要 | secretで渡すアクセスキー。 |
| `LENS_RUSTFS_SECRET_ACCESS_KEY` | endpointとともに必要 | secretで渡す秘密キー。 |
| `LENS_RUSTFS_REGION` | 任意 | 既定は`us-east-1`。 |
| `LENS_RUSTFS_TIMEOUT_MS` | 任意 | 1〜30000の整数。既定は30000。 |

RustFS変数を一つでも渡す場合、必須の4変数すべてに空でない値が必要。
不足設定・不正なtimeoutでは起動に失敗し、それ以外の不正設定は使用前に保存クライアントが拒否する。

PostgreSQLは識別・取得履歴・抽出／検索データを保持し、RustFSは新しいPDFバイト列を保持する。
読取時にはサイズ・SHA-256を検証し、別backendへの暗黙のfallbackや公開元からの再取得は行わない。
DB dumpはRustFS保存のPDFバイト列を含まない。
保持要件は[ADR 0005](adr/0005-store-pdfs-in-rustfs.md)に定める。

フィード購読はスケジューラーで定期実行する。
[検証手順](reference/earnings-value-validation.md)を参照する。

### DB の準備

同じイメージと`DATABASE_URL`を使い、アプリ起動前にDBを準備する。

```sh
/app/bin/lens eval 'Lens.Release.prepare()'
/app/bin/lens start
```

準備の終了後に常駐プロセスを起動する。両者は別々のコマンドとして実行する。
準備では Ecto マイグレーションで空 DB を初期化する。対応する旧
fingerprint を持つ既存 DB は Ecto の管理に引き継ぎ、未適用のマイグレーションを
実行する。起点は [ADR 0018](adr/0018-upgrade-postgresql-with-ecto-migrations.md) を参照。
最初の引き継ぎでは、旧版のデータと制約、および旧版が参照する fingerprint を保持する。
準備を再実行すると、`schema_migrations` に記録済みのマイグレーションはスキップされる。

準備に失敗したら旧版を稼働させたまま、エラーから更新を止めたスキーマや
マイグレーションを特定する。DB とリリースのバージョンを確認してから再試行する。
失敗したマイグレーションの変更はロールバックされ、それ以前に成功した変更は適用済みのまま残る。
原因調査中は既存 DB とマイグレーション履歴を保持する。

手動移行が必要なリリースでは、そのリリース固有の手順に従う。
保持データを変更する前に、復旧可能な PostgreSQL バックアップと対応する RustFS
オブジェクトを確認する。復元したコピーで手順を試し、記録と参照を検証する。
承認された手動作業の完了後に準備を再実行し、成功してから新版を起動する。
明示的に破棄可能な DB を再作成する場合は [ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md) に従う。

各プロセスがフィードschedulerを持つため、有効なアプリプロセスは1つとする。

| Endpoint | 意味 |
| --- | --- |
| `GET /api/health` | web processの稼働中に`200`を返す。 |
| `GET /api/ready` | PostgreSQLがqueryを受け付ければ`200`、それ以外は`503`。RustFSや公開元の可用性は確認しない。 |

使い方は[取得先の操作](operations.md)と[検索](search.md)を参照する。

</details>
