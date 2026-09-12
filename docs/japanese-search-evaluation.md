# Japanese Search Strategy Evaluation

This document records the bounded evaluation required before implementing
Japanese and CJK search. It does not change the current production search
behavior.

## Decision

Use PostgreSQL `pg_trgm` over a rebuildable, normalized derived text column
for Japanese/CJK substring retrieval. Keep the existing `simple` full-text
vector for Latin token search and use both derived indexes in the future search
query. PostgreSQL remains the only search datastore.

[`pg_trgm`](https://www.postgresql.org/docs/current/pgtrgm.html) is included
with the supported PostgreSQL 18 image and is enabled per database with
`CREATE EXTENSION pg_trgm`. A GIN index using `gin_trgm_ops` supports `LIKE`
and `ILIKE` substring predicates. The candidate provides useful matches for
unsegmented Japanese without adding a tokenizer service or a custom PostgreSQL
image.

The current `simple` text-search configuration is not selected for Japanese:
it treats uninterrupted Japanese text as one lexeme, so it cannot retrieve an
internal term such as `業績` from `業績予想`.

## Required Search Semantics

The implementation in #46 must preserve canonical title and content. It must
derive a separate search text by concatenating title and content, applying
Unicode NFKC normalization and Unicode lowercase mapping. Queries must use the
same normalization before being parameterized into an `ILIKE '%' || query ||
'%'` predicate.

- A normalized query must contain at least two Unicode graphemes and at least
  one letter or number. One-character and punctuation-only queries return the
  existing invalid-query response rather than issuing an unbounded query.
- Two or more Japanese characters perform exact normalized substring matching.
  The evaluation corpus defines expected matches and non-matches.
- Full-width and half-width Latin letters, spaces, and digits normalize to the
  same derived text. This is why the corpus includes both `PostgreSQL 18` and
  `ＰｏｓｔｇｒｅＳＱＬ　１８`.
- A match in the normalized title ranks above a body-only match. Stable document
  ID order remains the final tie-breaker.
- Existing API bounds remain in force: queries stay parameterized, limit is at
  most 100, and pagination is deterministic.

The query should combine the existing FTS predicate and the trigram substring
predicate without changing canonical data. A future migration should backfill
the derived text in bounded batches, create the GIN trigram index, and extend
`Lens.Search.rebuild/1` so it rebuilds both search representations without
fetching feeds. Rollback drops only the new derived column and index after the
application has stopped depending on them.

## Corpus and Reproduction

[`priv/evaluation/japanese_search_corpus.sql`](../priv/evaluation/japanese_search_corpus.sql)
contains synthetic documents and expected results for Japanese, mixed
Latin/numeric text, width normalization, punctuation rejection, and a
false-positive non-match. It contains no operational subscriptions or company
data.

Run the evaluation from a checkout with Docker available:

```sh
scripts/evaluate-japanese-search
```

The script starts a disposable PostgreSQL 18.6 container pinned to the same
digest as `compose.yml`, enables `pg_trgm`, validates every corpus expectation,
adds 10,000 unrelated synthetic documents, and prints an `EXPLAIN ANALYZE`
plan for a Japanese substring query. It removes the container after the run.

## Acceptance Threshold

The candidate is accepted only when every corpus assertion passes. Record the
planner-selected execution plan, observed execution time, and host resources
when rerunning this evaluation. A small corpus can legitimately use a sequential
scan even when the GIN index is available; this is a design check, not a scale
guarantee.

## Observed Result

The initial run used the pinned PostgreSQL 18.6 container on 2026-09-13. Docker
Engine 29.4.0 reported 12 CPUs and 25,274,273,792 bytes of memory. It validated
all corpus cases with 10,006 documents. PostgreSQL selected a sequential scan
for `前年同期比`, which completed in 7.926 ms; this small, highly cached corpus
did not justify the GIN index startup cost. The reproducible command prints the
measured plan and timing for each environment instead of claiming a portable
latency target.

## Implementation Checklist for #46

1. Add `pg_trgm`, a normalized derived search-text column, and its GIN index in
   a reversible migration.
2. Normalize derived text and queries with the same NFKC/lowercase function;
   reject one-character and punctuation-only queries before SQL execution.
3. Extend search ranking, pagination, and rebuild so FTS and trigram results
   remain deduplicated and title matches rank first.
4. Turn every corpus case into context and API regression coverage, including
   content changes and rebuild equivalence.
5. Run this script again and record the local dataset size, resources, plan,
   and timing in the implementation PR.
