---
status: accepted
---

# Publish manually registered investigation candidates through RSS

Separate the investigation-candidate publication boundary from automatic discovery and downstream notification delivery. Let the operator register a candidate through an API, persist its stable identity, and publish it through one unauthenticated local RSS feed. This permits a small, observable check that RSS can serve as a notification source before investing in candidate generation or a notification service. The agreed release boundary is tracked in [#185](https://github.com/9renpoto/lens/issues/185), with implementation and consumer verification in [#186](https://github.com/9renpoto/lens/issues/186).

An investigation candidate is a topic offered for further investigation, distinct from an acquired document candidate or an assessment of that document. The minimal publication contains a title, short body, optional details/evidence URL, and publication time. Preserve the candidate's stable item identity across repeated feed reads so a consumer can distinguish a new item from an already observed one. The full future candidate model need not become mandatory fields for this prototype.

Lens owns candidate registration, persistence, and RSS publication. Consumer notification, acknowledgement, read/delivery state, retries, multiple feeds, UI, automatic candidate generation, and production access control are outside this boundary. Detection by a conforming consumer demonstrates publication interoperability; it does not demonstrate discovery quality or delivery to a person. Use the local prototype within the application's existing private access boundary.

<details>
<summary>日本語</summary>

# 手動登録した調査候補をRSSで公開する

調査候補の公開を、自動的な発見と後続の通知配信から分離する。運用者がAPIから候補を登録し、安定した識別子とともに永続化して、認証なしのローカル単一RSSフィードで公開する。候補生成や通知サービスへ投資する前に、RSSを通知元として使えることを小さく観測可能な形で確認する。合意済みのリリース境界は[#185](https://github.com/9renpoto/lens/issues/185)、実装と購読側での検証は[#186](https://github.com/9renpoto/lens/issues/186)で追跡する。

調査候補は追加調査のために提示する論点であり、取得した資料候補やその資料の判定とは区別する。最小の公開内容は、タイトル、短い本文、任意の詳細・根拠URL、公開日時とする。フィードを繰り返し取得しても候補の項目識別子を維持し、購読側が新着と既に観測した項目を区別できるようにする。将来の完全な候補モデルを、このプロトタイプの必須フィールドにする必要はない。

Lensは候補登録、永続化、RSS公開を担当する。購読側の通知、確認、既読・配信状態、再試行、複数フィード、UI、候補の自動生成、本番アクセス制御はこの境界に含めない。標準に準拠する購読側の検出は公開の相互運用性を示すものであり、発見品質や人への通知到達は実証しない。ローカルのプロトタイプはアプリの既存の非公開アクセス境界内で使う。

</details>
