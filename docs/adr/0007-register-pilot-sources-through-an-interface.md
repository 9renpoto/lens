---
status: accepted
---

# Register analysis targets and feed sources through the operator API

Use `analysis_targets` as the issuer registry and `/api/sources` to configure
feeds. Registration does not establish publisher permission or document
identity. Review publisher conditions before enabling a feed and keep
acquisition separate from identity and operator decisions. Feed acquisition
follows [ADR 0017](0017-build-earnings-search-from-feed-updates.md).

The issuer registry records company identifiers and operator-managed
attributes. Historical index membership sits outside its scope because
configured feed collection identifies issuers independently of index inclusion.

Retire listing-source registration and the assessment workflow that depends on
it together. The old assessment records rely on the retired listing-source
registry for provenance. Keeping that registry would preserve a second source
model after listing acquisition has been retired. Initialize disposable
databases from the current schema under
[ADR 0010](0010-defer-backups-for-disposable-development-data.md). Old
registrations and assessment records are not transferred. Retained originals
in a supported database can still be read through the original API.

<details>
<summary>日本語</summary>

# 分析対象とフィード取得先を運用者 API で登録する

発行元台帳には `analysis_targets` を使い、フィードは `/api/sources` で設定する。
登録によって公開元の許可や資料の識別は確定しない。フィードを有効にする前に
公開元の条件を確認し、取得と識別・運用者判断を分離する。フィード取得には
[ADR 0017](0017-build-earnings-search-from-feed-updates.md) を適用する。

発行元台帳には企業の識別子と運用者が管理する属性を記録する。設定済みフィードの収集では
指数への組み入れとは独立して発行元を識別するため、指数の所属履歴は台帳の対象外とする。

一覧取得先の登録とそれに依存する判定処理を一緒に廃止する。旧判定記録の出典は
廃止対象の一覧取得先台帳に依存している。この台帳を残すと、一覧取得の廃止後も
二つ目の取得先モデルが残る。
[ADR 0010](0010-defer-backups-for-disposable-development-data.md) に従い、破棄可能な
DB を現行スキーマで初期化する。旧登録や判定記録は引き継がない。対応する DB に
保存された原本は引き続き原本 API で参照できる。

</details>
