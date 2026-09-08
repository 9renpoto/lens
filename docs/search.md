# Search API

Lens keeps canonical Documents in PostgreSQL. Its full-text vector and GIN
index are derived from each Document's title and plain-text content, so they
can be regenerated without fetching any source again.

## Query documents

`GET /api/search` requires `q`. It accepts optional `limit` (1 to 100, default
20) and `offset` (zero or greater, default 0). Queries use PostgreSQL
`websearch_to_tsquery` with the explicit `simple` configuration. Results are
ranked with titles above bodies and use document ID as the stable tie-breaker.

```sh
curl --get http://127.0.0.1:4000/api/search \
  --data-urlencode 'q=postgresql indexing' \
  --data-urlencode 'limit=20' \
  --data-urlencode 'offset=0'
```

Each result contains the document ID, title, canonical URL, publication time,
and a 300-character plain-text excerpt. `GET /api/documents/:id` returns the
canonical document content.

Empty or over-500-character queries, and malformed pagination values, return
`422`. Punctuation-only queries and queries with no matching indexed terms
return `200` with an empty `results` list. Query text is passed as a parameter,
never interpolated into SQL.

The `simple` configuration is intentionally the v0.1 baseline. It does not
provide Japanese/CJK morphological analysis, substring matching, or language
specific stemming. Search quality for Japanese and other CJK content is
therefore limited until a future, separately evaluated search approach is
introduced.

## Rebuild derived search data

From a development checkout, rebuild in bounded batches:

```sh
mix lens.search.rebuild --batch-size 1000
```

For the container deployment, run the same operation inside the release:

```sh
docker compose exec app /app/bin/lens eval 'Lens.Search.rebuild()'
```

The task only reads and updates canonical PostgreSQL documents. It does not
fetch feeds or change canonical content.
