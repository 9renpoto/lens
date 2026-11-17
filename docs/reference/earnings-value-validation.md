# Earnings-search value validation

Before enabling a feed source, review the publisher's current terms for the
intended acquisition, storage, extraction, search, display and redistribution.
The application neither interprets nor approves those terms. Record the source,
conditions and decision in private operational records; leave it disabled if
the decision is unresolved.

Lens's [MIT License](../../LICENSE) covers its code and accompanying
documentation, not the acquired PDF or text extracted from it. Personal,
non-commercial use without redistribution does not by itself establish that
a publisher permits the planned acquisition, storage, extraction and search.
Review those uses against the current terms, including any conditions specific
to the selected PDF. Preserve required publisher copyright notices with retained
materials and account for those requirements when extracting text and displaying
search results. Record the intended use and the operator's decision in the
private operational note; leave the source disabled if that decision is unresolved.

Use the [subscription guide](earnings-subscriptions.md) to acquire materials from
later feed updates. The first successful poll establishes a baseline without
acquiring existing entries. Use an isolated environment with disposable data
under [ADR 0010](../adr/0010-defer-backups-for-disposable-development-data.md).
Compare a searchable result with its retained original using the search API and
`GET /api/earnings/originals/:id`. The feed-material provenance URL identifies the
original when present. See the [material guide](earnings-materials.md) and
[search reference](../search.md). Do not infer confirmed release identity from
feed ingestion alone. Record only sanitized outcomes in public issues.

<details>
<summary>日本語</summary>

# 決算検索の価値検証

フィード取得先を有効にする前に、予定する取得・保存・抽出・検索・表示・再配布に関する
公開元の最新の条件を確認する。アプリは条件を解釈・承認しない。取得先、条件、判断を
非公開の運用記録に残し、判断が未確定なら取得先を無効のままにする。

Lens の [MIT License](../../LICENSE) はコードと付属文書に適用され、取得したPDFや
その抽出本文には適用されない。個人・非商用・再配布なしであることだけでは、
予定する取得・保存・抽出・検索を発行元が許容しているとは判断できない。
選定したPDF固有の条件も含め、最新の利用条件に照らしてこれらの用途を確認する。
保存資料には必要な発行元の著作権表示を保持し、本文抽出と検索結果の表示でも
その要件を考慮する。予定する用途と運用者の判断を非公開の運用メモに記録し、
判断が未確定の場合は取得先を無効のままにする。

[購読手順](earnings-subscriptions.md)に従い、後続のフィード更新から資料を取得する。
最初の成功した巡回は基準を記録し、既存項目を取得しない。
[ADR 0010](../adr/0010-defer-backups-for-disposable-development-data.md)に従う、
データを破棄可能な隔離環境を使う。検索 API と `GET /api/earnings/originals/:id` を
使い、検索結果と保存原本を比較する。フィード資料の出典 URL は、原本があればそれを
特定できる。[資料取得手順](earnings-materials.md)と[検索の参照情報](../search.md)を参照する。
フィード取り込みだけで短信識別が確定したと推測しない。公開 Issue には匿名化した結果のみを記録する。

</details>
