# Single-node operation

Lens runs as one application container and one PostgreSQL container. PostgreSQL
is the canonical store. Its named volume remains intact when application
containers are recreated.

## Deploy

Docker Engine with the Compose plugin is required. Make `POSTGRES_PASSWORD` and
`SECRET_KEY_BASE` available to Docker Compose before deploying. Generate a
unique value for `SECRET_KEY_BASE` and use a separate strong value for
`POSTGRES_PASSWORD`.

```sh
openssl rand -base64 48
```

Build the release locally, run migrations explicitly, and start the application:

```sh
docker compose build app
docker compose run --rm app /app/bin/lens eval 'Lens.Release.migrate()'
docker compose up -d app
```

After `Elixir CI` succeeds for a merge to `main`, Lens publishes
`ghcr.io/9renpoto/lens` with `latest` and a commit-specific `sha-...` tag. The
publish workflow retains the two newest GHCR package versions and deletes older
versions to keep storage within the free tier.

Confirm liveness and database readiness:

```sh
curl http://127.0.0.1:4000/api/health
curl http://127.0.0.1:4000/api/ready
```

The published API port is bound to loopback. Use an SSH tunnel or a trusted,
authenticated reverse proxy for remote access. Lens does not provide accounts
or public API authentication in v0.1. PostgreSQL has no published host port.

## Configure and inspect sources

Create an RSS, Atom, or existing RSSHub feed endpoint with the API. The
scheduler owns polling; RSSHub only returns feed output.

```sh
curl --fail-with-body http://127.0.0.1:4000/api/sources \
  -H 'content-type: application/json' \
  -d '{"source":{"source_type":"rss","endpoint_url":"https://feeds.example.com/feed.xml","poll_interval_seconds":900}}'

curl --fail-with-body http://127.0.0.1:4000/api/sources
curl --fail-with-body 'http://127.0.0.1:4000/api/search?q=example'
```

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

## Restart, backup, and restore

Restart the application without losing content:

```sh
docker compose restart app
```

Back up the canonical database while the stack is running:

```sh
docker compose exec -T postgres pg_dump -U lens -d lens > lens-backup.sql
```

To restore into a fresh Lens database, stop the stack, remove only the named
database volume, start PostgreSQL, then restore the dump:

```sh
docker compose down
docker volume rm lens_postgres_data
docker compose up -d postgres
cat lens-backup.sql | docker compose exec -T postgres psql -U lens -d lens
docker compose up -d app
```

If an explicit migration fails, keep the volume, inspect the error with
`docker compose logs app`, correct the deployment, and rerun the migration
command. Never delete the volume as a migration recovery step.
