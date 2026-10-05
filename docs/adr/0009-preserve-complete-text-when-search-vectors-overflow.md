---
status: accepted
---

# Preserve complete text when search vectors overflow

Record the existing earnings search choice: retain complete successful text when PostgreSQL cannot represent its full-text vector. Use complete normalized substring matching for that text and expose vector availability through `search_mode` and `full_text_complete`.

Truncating text to fit an index would lose searchable material and hide the loss. Substring fallback preserves the text but cannot support full-text boolean or phrase operators; reporting its mode makes that limitation visible. See [the search contract](../search.md) for field semantics.

This replaces the historical size-design plan, not the remaining v0.2 discussion about selected versions and search behavior.

<details>
<summary>日本語</summary>

# 検索ベクトルの上限を超えても本文全体を保持する

既存の決算検索方式を記録する。PostgreSQLで全文検索ベクトルを表現できない場合も、成功した本文全体を保持する。その本文では全体を正規化した文字列の部分一致を使い、`search_mode`と`full_text_complete`でベクトルの利用可否を示す。

索引のために本文を切り詰めると検索対象の情報を失い、その欠落が見えなくなる。部分一致への切替なら本文を保持できるが、全文検索の論理・句演算子は使えない。検索方式を表示して制限を見えるようにする。項目の意味は[検索の契約](../search.md)を参照する。

過去のサイズ設計プランを置き換えるものであり、残るv0.2の対象版・検索挙動の議論を確定するものではない。

</details>
