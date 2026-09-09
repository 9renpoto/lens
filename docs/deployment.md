# Production deployment

This document defines the application contract for deploying Lens from a
published container image. It is intended for an operator who manages a
Kustomize environment. It does not prescribe a Kubernetes distribution,
database service, ingress controller, TLS provider, secret manager, or image
pull mechanism.

## Image version policy

Production workloads must reference a released image tag such as `v0.1.0`.
Do not deploy `latest` or a commit-specific `sha-...` tag. A release tag makes
the deployed version explicit and lets tools such as Dependabot propose a
reviewable update to the Kustomize image reference.

Images are published to `ghcr.io/9renpoto/lens`. Release-tag publishing is a
separate delivery concern from this deployment contract. Before creating a
production workload, ensure the selected release tag exists and the deployment
environment can pull it.

The GHCR package retains only the two newest image versions. Keep the deployed
release and its rollback candidate within that retention window. Operators who
need a longer rollback history must provide it in their own image registry or
backup process.

## Required infrastructure

Lens requires the following services and capabilities:

- A runtime that can run the Linux container image and expose its TCP port.
- PostgreSQL reachable from the application. PostgreSQL is the canonical store
  and requires durable storage, backups, and a restore procedure.
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
user. It needs no writable application filesystem volume. Only PostgreSQL data
requires persistent storage.

Generate `SECRET_KEY_BASE` with a cryptographically secure random generator.
Do not reuse the database password or a value from another service.

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
