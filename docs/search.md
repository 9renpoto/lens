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
# Earnings search

Retained earnings PDFs join ordinary search after successful extraction. Each
logical release contributes its newest eligible successful original only; older
successful text stays selected with `stale: true` when a newer original is pending
or failed. Selection precedes matching and global pagination across feed and
earnings results. Search uses the existing CJK normalizer and the rebuild task
also regenerates extraction search fields from plain text without publisher access.
See [earnings extraction](earnings-extraction.md) for commands, deterministic
ordering, result fields and `GET /api/earnings/releases/:id` inspection.

Successful earnings text is retained in full even when its PostgreSQL full-text
vector exceeds the database size limit. Such text uses complete normalized
literal substring matching and a full-text rank of zero; boolean and phrase
full-text operators are unavailable for that text. Results expose `search_mode`
as `full_text` or `substring`; release attempt details also use `none` for
pending/failed attempts. Search responses include `full_text_complete`, false
when any selected eligible earnings text lacks a vector, even when the page has
no results. Coverage and results are computed in one database snapshot before
matching and pagination. This flag reports vector availability, not semantic
search completeness or Japanese morphological analysis. Feed matching is unchanged.

<details>
<summary>日本語</summary>

## 決算本文の検索

保存した決算PDFは抽出成功後に通常検索へ加わる。論理短信ごとに対象原本の最新成功版1件を使い、
新しい原本が待機・失敗の場合は旧成功本文を `stale: true` で維持する。選択は照合と
フィード・短信全体のページングより先に行う。既存CJK正規化を使い、再構築タスクも発行元通信なしで
抽出本文から検索フィールドを再生成する。コマンド、決定的順序、結果項目、
`GET /api/earnings/releases/:id` による確認は[抽出説明](earnings-extraction.md)を参照。

PostgreSQLの全文検索ベクトルがDBサイズ制約を超えても、成功した決算本文は全文を保持する。
その本文では全文の正規化済み文字列部分一致を使い、全文順位は0とする。全文検索の論理・句
演算子は利用できない。検索結果の `search_mode` は `full_text` または `substring`。
原本の抽出詳細では待機・失敗に `none` も使う。検索応答の `full_text_complete` は、選択済み
対象本文にベクトルなしがあれば、0件のページでもfalseになる。対象の利用可否と結果は
同じDBスナップショットで、照合・ページング前に計算する。これはベクトル利用可否を示し、
意味検索の完全性や日本語形態素解析を示すものではない。フィードの照合は維持する。

</details>
