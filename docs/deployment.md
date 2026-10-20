# Production deployment

This document defines the application contract for deploying Lens from a
published container image. It is intended for an operator who manages a
Kustomize environment. It does not prescribe a Kubernetes distribution,
database service, ingress controller, TLS provider, secret manager, or image
pull mechanism.

## Image version policy

Production workloads must reference a released image tag in the form
`vMAJOR.MINOR.PATCH`, such as `v0.1.0`. Release tags with pre-release or build
metadata are not supported in v0.1. Do not deploy `latest` or a commit-specific
`sha-...` tag. A release tag makes the deployed version explicit and lets tools
such as Dependabot propose a reviewable update to the Kustomize image reference.

Images are published to `ghcr.io/9renpoto/lens`. The repository's version bump
workflow updates the application version and prepares a release PR. After that
PR is merged, create the release tag manually on the merge commit. Pushing the
tag starts CI, and the matching release-tagged image is published only after
its tests pass.
The release tag, `latest`, and its commit-specific `sha-...` tag are produced
from the same image build. The `latest` tag therefore advances on successful
pushes to `main` and on successful release tag publication; production
deployments should continue to use the immutable release tag.
Before creating a production workload, ensure the selected release tag exists
and the deployment environment can pull it anonymously or with its configured
registry credentials.

The GHCR package retains only the two newest tagged image versions. Untagged
manifests are retained when they may be children of a kept multi-platform
index, so cleanup cannot make a retained release unpullable. Keep the deployed
release and its rollback candidate within the two-tag window. Operators who
need a longer rollback history must provide it in their own image registry or
backup process.

## Create a release tag

Run the version bump workflow and merge its release PR into `main`. Record the
merge commit and the version written to `mix.exs`, then create an annotated tag
on that exact commit:

```sh
git fetch origin main
git tag --list 'v*.*.*'
git tag -a v0.1.0 <merge-commit> -m "Release v0.1.0"
git push origin v0.1.0
```

Replace `v0.1.0` and `<merge-commit>` with the values from the merged release
PR. The tag must match `vMAJOR.MINOR.PATCH`; pre-release and build metadata are
unsupported. The tag push runs the normal CI test job and publishes the release
image only when the tests pass. Do not reuse an existing release tag.

## Required infrastructure

Lens requires the following services and capabilities:

- A runtime that can run the Linux container image and expose its TCP port.
- The latest PostgreSQL major version supported by the PostgreSQL project,
  reachable from the application. PostgreSQL is the canonical store and
  requires durable storage, backups, and a restore procedure. Lens currently
  supports PostgreSQL 18.
- Secret delivery for the database connection string and Phoenix secret key.
- Network access from Lens to configured feed endpoints. This includes any
  RSSHub instance used as a feed endpoint.
- A way to restrict access to the HTTP API. Lens has no authentication or
  authorization in v0.1.
- Access to `ghcr.io` for image pulls when the image package is private.

Choose how these capabilities are supplied in the target environment. For
example, PostgreSQL may be an existing managed service or a stateful workload;
TLS and API access may be provided by an ingress, reverse proxy, private
network, or another appropriate boundary.

Lens tracks the latest supported PostgreSQL major version. A future major
version change requires a separately reviewed compatibility update. Minor image
updates are pinned by digest and tracked by Dependabot.

## Application configuration

Pass configuration as environment variables. Store secrets in the deployment
environment's secret mechanism rather than in a Kustomize repository.

| Variable | Required | Description |
| --- | --- | --- |
| `DATABASE_URL` | Yes | PostgreSQL Ecto URL, for example `ecto://lens:PASSWORD@postgres.example/lens`. |
| `SECRET_KEY_BASE` | Yes | Unique high-entropy Phoenix secret. Generate and store it as a secret. |
| `PHX_HOST` | Yes | Public host name used when Lens generates URLs. |
| `PORT` | No | HTTP listen port. Defaults to `4000`. |
| `POOL_SIZE` | No | PostgreSQL connection-pool size. Defaults to `10`. Size it within the database connection budget. |

The container listens on `0.0.0.0:$PORT` and runs as the unprivileged `lens`
user. It needs no writable application filesystem volume. PostgreSQL data and
any RustFS objects holding retained originals require persistent storage.

Generate `SECRET_KEY_BASE` with a cryptographically secure random generator.
Do not reuse the database password or a value from another service.

## Earnings PDF storage

Registered-source earnings collection requires RustFS in addition to PostgreSQL.
Provision the bucket and supply these variables through the deployment's secret
and configuration mechanisms:

| Variable | Requirement | Description |
| --- | --- | --- |
| `LENS_RUSTFS_ENDPOINT` | Required for collection and RustFS-backed reads | RustFS HTTP(S) endpoint. |
| `LENS_RUSTFS_BUCKET` | Required with endpoint | Bucket for retained originals. |
| `LENS_RUSTFS_ACCESS_KEY_ID` | Required with endpoint | Access key delivered as a secret. |
| `LENS_RUSTFS_SECRET_ACCESS_KEY` | Required with endpoint | Secret key delivered as a secret. |
| `LENS_RUSTFS_REGION` | Optional | Defaults to `us-east-1`. |
| `LENS_RUSTFS_TIMEOUT_MS` | Optional | Integer from 1 to 30000; defaults to 30000. |

If any RustFS variable is supplied, all four required values must be nonempty.
Partial configuration or an invalid timeout fails startup; the storage client
rejects other invalid configuration before collection. With no RustFS configuration,
the collector returns `{:error, :not_configured}` before publisher requests.
Existing PostgreSQL-backed originals remain readable through their recorded
storage location; unavailable RustFS objects are not silently read from another
backend or fetched again from the publisher.

PostgreSQL retains identity, acquisition history, storage-work records, and
extraction/search data. RustFS retains new PDF bytes. A PostgreSQL dump alone
cannot restore RustFS-backed originals. Before retaining non-disposable records
or operating in production, provide coordinated PostgreSQL/RustFS backup and
recovery as required by [ADR 0005](adr/0005-store-pdfs-in-rustfs.md).

The local k3s v0.2 pilot uses explicitly disposable development/test data under
[ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md). Its
[bounded manual procedure](reference/earnings-value-validation.md) does not
establish production recovery guarantees. Earnings collection is invoked
manually; the feed scheduler does not schedule it.

<details>
<summary>日本語</summary>

## 決算PDFの保存

コンテナは非特権の`lens`ユーザーで動作し、書込可能なアプリ用volumeを必要としない。
PostgreSQLデータと、保持原本を格納するRustFSオブジェクトには永続保存が必要。

登録済み取得先の決算収集にはPostgreSQLに加えてRustFSが必要。バケットを用意し、
配備先のsecret・設定管理を通じて次の変数を渡す。

| 変数 | 要件 | 説明 |
| --- | --- | --- |
| `LENS_RUSTFS_ENDPOINT` | 収集・RustFS保存原本の読取に必要 | RustFSのHTTP(S) endpoint。 |
| `LENS_RUSTFS_BUCKET` | endpointとともに必要 | 原本を保持するバケット。 |
| `LENS_RUSTFS_ACCESS_KEY_ID` | endpointとともに必要 | secretで渡すアクセスキー。 |
| `LENS_RUSTFS_SECRET_ACCESS_KEY` | endpointとともに必要 | secretで渡す秘密キー。 |
| `LENS_RUSTFS_REGION` | 任意 | 既定は`us-east-1`。 |
| `LENS_RUSTFS_TIMEOUT_MS` | 任意 | 1〜30000の整数。既定は30000。 |

RustFS変数を一つでも渡す場合、必須の4変数すべてに空でない値が必要。
不足設定・不正なtimeoutでは起動に失敗し、それ以外の不正設定は収集前に保存クライアントが拒否する。RustFS設定がなければ、Collectorは公開元へ
通信する前に`{:error, :not_configured}`を返す。既存のPostgreSQL保存原本は
記録された保存場所を通じて読み取れる。RustFSオブジェクトが利用できない場合に、
別バックエンドから暗黙に読み取ったり、公開元から再取得したりしない。

PostgreSQLは識別・取得履歴・保存作業記録・抽出／検索データを保持し、RustFSは
新しいPDFバイト列を保持する。PostgreSQLのdumpだけではRustFS保存原本を復元できない。
破棄できない記録の保持開始前または本番運用前には、
[ADR 0005](adr/0005-store-pdfs-in-rustfs.md)に従うPostgreSQL/RustFSの協調バックアップ・復旧を用意する。

ローカルk3s上のv0.2パイロットは[ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md)
に従い、明示的に破棄可能な開発・テストデータを使う。
[上限付き手動手順](reference/earnings-value-validation.md)は本番復旧の保証を確立しない。
決算収集は手動で呼び出し、フィードのschedulerは決算収集を定期実行しない。

</details>

## Deploy a release

Configure the workload to use the released image tag, required environment
variables, and a private Service or equivalent network endpoint. Before
starting or updating the long-running application workload, run the release
migration command once against the target database:

```sh
/app/bin/lens eval 'Lens.Release.migrate()'
```

Run it as a deployment Job, hook, or equivalent one-shot workload using the
same image and `DATABASE_URL` as the application. The migration command is
safe to rerun; it applies outstanding Ecto migrations only. Do not run multiple
migration workloads concurrently for the same database.

After the migration succeeds, roll out the application workload. A single
replica is the v0.1 deployment model. Lens owns its source scheduler, so a
second active replica would duplicate polling work.

Use these HTTP endpoints for probes:

| Endpoint | Purpose |
| --- | --- |
| `GET /api/health` | Process liveness. Returns `200` when the web process is running. |
| `GET /api/ready` | Readiness. Returns `200` only when PostgreSQL accepts a query; otherwise it returns `503`. |

Expose the API only through an access boundary that is appropriate for a
single-user, unauthenticated application. Do not publish it directly to an
untrusted network.

## Update and rollback

Update the Kustomize image reference to the next release tag and review the
resulting change. Run migrations before rolling out that image, then verify
`/api/ready` and the workload logs.

To roll back the application, restore the previous release tag while it remains
available. Database migrations are forward-only in v0.1, so confirm migration
compatibility before treating an image rollback as a full database rollback.
Back up PostgreSQL before upgrades and restore from that backup when a database
rollback is required.

## Operational checks

After deployment, confirm all of the following:

- The selected release tag is recorded in the deployed Kustomize configuration.
- The migration workload completed successfully.
- `/api/health` and `/api/ready` return `200` through the intended network path.
- PostgreSQL backups and restore instructions are available to the operator.
- Application logs show scheduled ingestion attempts after sources are
  configured.

For source management, search behavior, and rebuilding derived search data,
see [operations](operations.md) and the [search API](search.md).
