---
status: accepted
---

# Use PostgreSQL for Japanese substring search

Keep canonical text in PostgreSQL and derive NFKC/lowercase search text indexed with `pg_trgm`, alongside `simple` full-text search. Japanese queries use literal substring matching.

This allows Japanese text matching without operating another search service or maintaining a tokenizer dictionary. It does not provide morphological, semantic or translated search. Keep canonical text unchanged so derived fields can be rebuilt when the method changes. See [search operations](../search.md).


<details>
<summary>日本語</summary>

# 日本語の部分一致検索にPostgreSQLを使う

原文をPostgreSQLに保持し、NFKC・小文字化した検索用本文を`pg_trgm`で索引化して、`simple`全文検索と併用する。日本語の検索には文字列の部分一致を使う。

別の検索サービスや分かち書き辞書を運用せず、日本語の文字列を検索できる。形態素解析・意味検索・翻訳検索は提供しない。原文を変更せず、方式を変えた場合も検索用項目を再構築できるようにする。[検索操作](../search.md)を参照する。


</details>
