# Lens

[![codecov](https://codecov.io/gh/9renpoto/lens/graph/badge.svg?token=fKDe4hKp4e)](https://codecov.io/gh/9renpoto/lens)

Lens is a self-hosted, single-user Personal Web Observatory. It accumulates
useful information over time through a simple flow:

```text
Collect → Preserve → Search → Discover
```

Version 0.1 concentrates on the first three steps: scheduled RSS and Atom feed
collection (including output from an existing RSSHub endpoint), normalization
to canonical plain text, PostgreSQL persistence, and PostgreSQL full-text
search through a JSON API.

Lens is independent from the experimental offline-first RSS reader. A future
integration, if useful, will use a loose API boundary rather than a shared
application model.

## Status

The project is under active initial development. The v0.1 plan is tracked in
[GitHub milestone v0.1](https://github.com/9renpoto/lens/milestone/1).

It intentionally excludes LLMs, embeddings, vector databases, external search
engines, browser automation, custom web crawling, multi-tenancy, and
distributed deployment. Proactive discovery and recommendations are future
experiments, not v0.1 requirements.

## Architecture

Lens runs as one Elixir/OTP application with Phoenix as its JSON API layer and
PostgreSQL as its canonical datastore. The application owns source scheduling;
RSSHub is only a replaceable feed acquisition endpoint.

Canonical data consists of Sources, Documents, and Observations. PostgreSQL
full-text vectors are derived data and can be rebuilt without fetching sources
again. The initial content representation is meaningful plain text with
paragraph breaks, not raw HTML or a complex content AST.

## Development setup

Requirements: Elixir 1.18 / Erlang-OTP 27 and PostgreSQL 17. For the initial
development environment, install PostgreSQL with Homebrew:

```sh
brew install postgresql@17
brew services start postgresql@17
```

Install dependencies and create the development database:

```sh
mix setup
```

Start the API:

```sh
mix phx.server
```

The initial health endpoint is available at `GET /api/health`.

Run the checks used by CI:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

`POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `PORT`,
and `POOL_SIZE` can override local defaults.

## Operations

See [production deployment](docs/deployment.md) for the Kustomize deployment
contract and [single-node operations](docs/operations.md) for local Compose
operation, backups, restores, and failure recovery. See the [search
API](docs/search.md) for PostgreSQL FTS behavior, its current Japanese/CJK
limitations, and search data rebuilds.

## License

Lens is licensed under the [MIT License](LICENSE).
