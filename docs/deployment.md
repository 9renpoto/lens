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
- RustFS stores newly collected earnings PDFs. Existing PostgreSQL-backed
  originals remain readable through their recorded storage location.
- Configured feed and earnings sources must be reachable from the application.
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

[ADR 0013](adr/0013-retire-interrupted-storage-recovery.md) retires interrupted-write recovery for bounded disposable-data validation. Runtime removal is pending #195; existing storage-work records are transitional. This decision does not change the original-preservation boundary or establish production restore guarantees.

Registered-source earnings collection requires a provisioned RustFS bucket and
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
rejects other invalid configuration before collection. With no RustFS
configuration, the collector returns `{:error, :not_configured}` before
publisher requests.

PostgreSQL retains identity, acquisition history, storage-work records, and
extraction/search data. RustFS retains new PDF bytes. Reads verify size and
SHA-256 and do not silently fall back to another backend or refetch the
publisher. A database dump does not contain RustFS-backed PDF bytes;
preservation requirements are defined in [ADR 0005](adr/0005-store-pdfs-in-rustfs.md).


Earnings collection is invoked manually; the feed scheduler does not schedule
it. Follow the [bounded validation procedure](reference/earnings-value-validation.md).

## Application commands and health

Apply outstanding migrations before starting the application, using the same
image and `DATABASE_URL`:

```sh
/app/bin/lens eval 'Lens.Release.migrate()'
/app/bin/lens start
```

Run these as separate commands: let migration finish before starting the
long-running process. Migration applies outstanding Ecto migrations only and
is safe to rerun. Do not run concurrent migrations against the same database.
Use one active application process because each process owns its feed scheduler.
Migrations are forward-only; changing the application image does not undo a
database migration.

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
- RustFSは新たに収集する決算PDFを保存する。既存のPostgreSQL保存原本は
  記録された保存場所を通じて読み取れる。
- 設定したフィード・決算取得先へアプリから接続できる必要がある。
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

[ADR 0013](adr/0013-retire-interrupted-storage-recovery.md)に従い、上限付き・破棄可能データの検証では中断書き込みの復旧を廃止する。実行時機能の削除は#195待ちで、既存の保存作業記録は移行中のものとする。この判断で原本保持の境界は変わらず、本番復元の保証も確立しない。

登録済み取得先の決算収集には、用意済みのRustFSバケットと次の設定が必要。

| 変数 | 要件 | 説明 |
| --- | --- | --- |
| `LENS_RUSTFS_ENDPOINT` | 収集・RustFS保存原本の読取に必要 | RustFSのHTTP(S) origin。隔離された信頼済みネットワーク外ではHTTPSを必須とする。 |
| `LENS_RUSTFS_BUCKET` | endpointとともに必要 | 原本を保持するバケット。 |
| `LENS_RUSTFS_ACCESS_KEY_ID` | endpointとともに必要 | secretで渡すアクセスキー。 |
| `LENS_RUSTFS_SECRET_ACCESS_KEY` | endpointとともに必要 | secretで渡す秘密キー。 |
| `LENS_RUSTFS_REGION` | 任意 | 既定は`us-east-1`。 |
| `LENS_RUSTFS_TIMEOUT_MS` | 任意 | 1〜30000の整数。既定は30000。 |

RustFS変数を一つでも渡す場合、必須の4変数すべてに空でない値が必要。
不足設定・不正なtimeoutでは起動に失敗し、それ以外の不正設定は収集前に保存クライアントが拒否する。
RustFS設定がなければ、Collectorは公開元への通信前に`{:error, :not_configured}`を返す。

PostgreSQLは識別・取得履歴・保存作業記録・抽出／検索データを保持し、RustFSは新しいPDFバイト列を保持する。
読取時にはサイズ・SHA-256を検証し、別backendへの暗黙のfallbackや公開元からの再取得は行わない。
DB dumpはRustFS保存のPDFバイト列を含まない。
保持要件は[ADR 0005](adr/0005-store-pdfs-in-rustfs.md)に定める。

決算収集は手動で呼び出し、フィードのschedulerは定期実行しない。
[上限付き検証手順](reference/earnings-value-validation.md)を参照する。

## アプリのコマンドと稼働確認

同じイメージと`DATABASE_URL`を使い、アプリ起動前に未適用migrationを適用する。

```sh
/app/bin/lens eval 'Lens.Release.migrate()'
/app/bin/lens start
```

migrationの終了後に常駐プロセスを起動する、別々のコマンドとして実行する。
migrationは未適用のEcto migrationだけを適用し、再実行できる。
同じDBへ同時にmigrationを実行しない。
各プロセスがフィードschedulerを持つため、有効なアプリプロセスは1つとする。
migrationは前方適用のみで、アプリのイメージ変更ではDB migrationを元に戻せない。

| Endpoint | 意味 |
| --- | --- |
| `GET /api/health` | web processの稼働中に`200`を返す。 |
| `GET /api/ready` | PostgreSQLがqueryを受け付ければ`200`、それ以外は`503`。RustFSや公開元の可用性は確認しない。 |

使い方は[取得先の操作](operations.md)と[検索](search.md)を参照する。

</details>
