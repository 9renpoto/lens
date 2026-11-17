---
status: accepted
---

# Register analysis targets and feed sources through the operator API

Use `analysis_targets` as the shared registry for company identifiers and
operator-managed attributes. Configure feeds through `/api/sources`.
Registration does not establish publisher permission or document
identity. Review publisher conditions before enabling a feed and keep
acquisition separate from identity and operator decisions. Feed acquisition
follows [ADR 0017](0017-build-earnings-search-from-feed-updates.md).

<details>
<summary>日本語</summary>

# 分析対象とフィード取得先を運用者 API で登録する

企業の識別子と運用者が管理する属性の共通台帳には `analysis_targets` を使い、
フィードは `/api/sources` で設定する。
登録によって公開元の許可や資料の識別は確定しない。フィードを有効にする前に
公開元の条件を確認し、取得と識別・運用者判断を分離する。フィード取得には
[ADR 0017](0017-build-earnings-search-from-feed-updates.md) を適用する。

</details>
