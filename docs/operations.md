# Local application operation

Lens runs as one application container and one PostgreSQL container. PostgreSQL
is the canonical store. Its named volume remains intact when application
containers are recreated.

The Compose stack uses the latest PostgreSQL major version supported by the
PostgreSQL project (currently PostgreSQL 18). Its minor release and image digest
are pinned for reproducibility, and Dependabot proposes image updates.
PostgreSQL 18's official image stores data under
`/var/lib/postgresql/18/docker`; the named volume therefore mounts
`/var/lib/postgresql`.

This document covers application usage with the repository's local Compose
stack. The [runtime contract](deployment.md) defines the application interface.

<details>
<summary>日本語</summary>

## 取得先の分類

`feed_format`は`rss_2_0`・`atom`・`rss_1_0`・`unknown`、
`acquisition_kind`は`direct`・`conversion_service`・`rsshub`・`unknown`、
`publisher_authority`は`official`・`third_party`・`unknown`を指定する。
`original_feed_url`は任意で、認証情報を含めない。省略した分類は`unknown`とし、
判明している分類は個別に明示する。取得先と出典の応答はこの独立した分類を返す。

この文書はリポジトリ付属のローカルCompose構成でのアプリ操作を扱う。
アプリのinterfaceは[実行契約](deployment.md)を参照する。

</details>

## Deploy

Docker Engine with the Compose plugin is required. Make `POSTGRES_PASSWORD` and
`SECRET_KEY_BASE` available to Docker Compose before deploying. Generate a
unique value for `SECRET_KEY_BASE` and use a separate strong value for
`POSTGRES_PASSWORD`.

```sh
openssl rand -base64 48
```

Build the release locally, prepare the database explicitly, and start the application:

```sh
docker compose build app
docker compose run --rm app /app/bin/lens eval 'Lens.Release.prepare()'
docker compose up -d app
```

Confirm liveness and database readiness:

```sh
curl http://127.0.0.1:4000/api/health
curl http://127.0.0.1:4000/api/ready
```

Open `http://127.0.0.1:4000/dashboard` for a mobile-friendly, server-rendered
overview of source, document, and observation counts. The page has no client-side
data fetching; reload it to see current values.

The published API port is bound to loopback. Use an SSH tunnel or a trusted,
authenticated reverse proxy for remote access. Lens does not provide accounts
or public API authentication in v0.1. PostgreSQL has no published host port.

## Configure and inspect sources

Create a source with the API. Feed format, acquisition kind, and publisher
authority are distinct values: an RSSHub route can relay an official Atom feed,
but RSSHub alone does not establish publisher authority. The scheduler owns
polling; RSSHub only returns feed output.

```sh
curl --fail-with-body http://127.0.0.1:4000/api/sources \
  -H 'content-type: application/json' \
  -d '{"source":{"feed_format":"atom","acquisition_kind":"rsshub","publisher_authority":"official","original_feed_url":"https://publisher.example.test/news.atom","acquisition_metadata":{"route":"example/news"},"endpoint_url":"https://rsshub.example.test/example/news","poll_interval_seconds":900}}'

curl --fail-with-body http://127.0.0.1:4000/api/sources
curl --fail-with-body 'http://127.0.0.1:4000/api/search?q=example'
```

Allowed values are `rss_2_0`, `atom`, `rss_1_0`, or `unknown` for
`feed_format`; `direct`, `conversion_service`, `rsshub`, or `unknown` for
`acquisition_kind`; and `official`, `third_party`, or `unknown` for
`publisher_authority`. `original_feed_url` is optional and must not contain
credentials. Omitted classifications remain `unknown`; set each classification
explicitly when it is known. The source and provenance responses return these
independent classification fields.

New enabled sources are immediately due, so the scheduler performs their first
fetch without a manual command. To diagnose a failed source, inspect its
`last_error`, `last_attempt_at`, `last_success_at`, `failure_count`, and
`next_fetch_at` values in `GET /api/sources`, then inspect application logs:

```sh
docker compose logs --tail=200 app
```

Each ingestion completion log includes the source ID, outcome, duration, and
valid/invalid entry counts. It excludes feed bodies and endpoint URLs.

For a manual diagnostic fetch, run `mix lens.ingest SOURCE_ID` from a local
development checkout. Do not use an unauthenticated public RSSHub instance for
private feeds.

## Smoke and soak checks

The deterministic vertical-slice test uses only local RSS and Atom/RSSHub-style
fixtures. It verifies source creation through the API, ingestion, changed
content, PostgreSQL search, and an injected feed failure:

```sh
mix test test/system/vertical_slice_test.exs --seed 0
```

Run the same check once per minute for one hour before a home-server upgrade or
after changing the deployment:

```sh
scripts/soak 60
```

The command exits at the first failed iteration and prints the iteration number.
Record the command output, Lens version, host resources, and any failure in the
deployment change record. It is an operator check, not a CI gate or a scale
guarantee.

## Retained data

The local Compose feed stack stores canonical data in PostgreSQL. If the
application also references RustFS-backed originals, those PDF bytes reside in
RustFS and are not included in a database dump. See the
[runtime contract](deployment.md#earnings-pdf-storage) for the storage boundary
and [ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md) for
disposable development/test data.

<details>
<summary>日本語</summary>

## 取得先の分類

`feed_format`は`rss_2_0`・`atom`・`rss_1_0`・`unknown`、
`acquisition_kind`は`direct`・`conversion_service`・`rsshub`・`unknown`、
`publisher_authority`は`official`・`third_party`・`unknown`を指定する。
`original_feed_url`は任意で、認証情報を含めない。省略した分類は`unknown`とし、
判明している分類は個別に明示する。取得先と出典の応答はこの独立した分類を返す。

## 保持するデータ

ローカルComposeのフィード用構成は、正となるデータをPostgreSQLへ保存する。
アプリがRustFS保存原本も参照する場合、そのPDFバイト列はRustFSにありDB dumpには含まれない。
保存の境界は[実行契約](deployment.md#earnings-pdf-storage)、
破棄可能な開発・テストデータは[ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md)
を参照する。

</details>
