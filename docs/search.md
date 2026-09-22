# Search API

Lens keeps canonical Documents in PostgreSQL. Its full-text vector, normalized
search text, and GIN indexes are derived from each Document's title and
plain-text content, so they can be regenerated without fetching any source
again.

## Query documents

`GET /api/search` requires `q`. It accepts optional `limit` (1 to 100, default
20) and `offset` (zero or greater, default 0). Queries use PostgreSQL
`websearch_to_tsquery` with the explicit `simple` configuration and a
PostgreSQL `pg_trgm` substring predicate. Results are ranked with normalized
title matches above body-only matches and use document ID as the stable
tie-breaker.

```sh
curl --get http://127.0.0.1:4000/api/search \
  --data-urlencode 'q=postgresql indexing' \
  --data-urlencode 'limit=20' \
  --data-urlencode 'offset=0'
```

Each result contains the document ID, title, canonical URL, publication time,
a 300-character plain-text excerpt, and a stable `provenance_url` reference
(`/api/documents/:id/provenance`). `GET /api/documents/:id` returns the
canonical document content, source summaries, and `provenance_url`.

## Document observation provenance

`GET /api/documents/:id/provenance` returns the full acquisition history behind a
canonical document with bounded pagination (`limit` 1 to 100, default 20; `offset`
default 0). Observations are ordered deterministically (latest `observed_at`
first).

Each observation includes:
- Observation ID and Source ID
- UTC observation time (`observed_at`) and reported publication time (`reported_published_at`)
- SHA-256 content hash
- Known primary/entry references (`entry_url`, `primary_source_url`)
- Feed format, acquisition kind, and publisher authority classification snapshots
- Acquisition metadata snapshot

Operational source endpoint URLs and credentials are redacted and never returned
in provenance responses. Invalid pagination values return `422`. Missing or malformed
document IDs return `404`.

Empty, one-character, punctuation-only, or over-500-character queries, and
malformed pagination values, return `422`. Queries with no matching indexed
terms return `200` with an empty `results` list. Query text is passed as a
parameter and `%`, `_`, and backslash are treated as literal characters.

Japanese and other CJK text uses normalized substring matching. Lens applies
Unicode NFKC normalization and lowercase mapping to derived search data and
queries, so full-width and half-width Latin letters, spaces, and digits match
each other. This is not Japanese morphological analysis, stemming, translation,
or semantic search.

The database migration enables PostgreSQL's `pg_trgm` extension and creates the
derived GIN index. Roll back only after an application version that no longer
depends on the derived columns is deployed; canonical Documents are unchanged.

## Rebuild derived search data

From a development checkout, rebuild in bounded batches:

```sh
mix lens.search.rebuild --batch-size 1000
```

For the container deployment, run the same operation inside the release:

```sh
docker compose exec app /app/bin/lens eval 'Lens.Search.rebuild()'
```

The task only reads canonical PostgreSQL documents and regenerates derived
search data in bounded batches. It does not fetch feeds or change canonical
content.
