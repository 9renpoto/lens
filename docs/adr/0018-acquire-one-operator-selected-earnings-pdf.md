---
status: accepted
---

# Acquire one operator-selected earnings PDF

For [#265](https://github.com/9renpoto/lens/issues/265), the person specifying the
source verifies its correctness, the publisher's conditions, and the release's
publication time before acquisition. A manual run takes one enabled registered
listing source and the complete URL of one verified PDF. Lens resolves the listing's
PDF links and acquires the specified URL only when exactly one anchor matches.
The query string is part of the match. Listing order cannot authorize a download.
This keeps selection independent of publisher-specific dates and naming conventions
while preserving listing provenance under [ADR 0007](0007-register-pilot-sources-through-an-interface.md).

Stop if the listing cannot be read within the collection bounds, the link is missing
or ambiguous, or the URLs violate the transport policy. Use the reviewed URLs
without following redirects in this mode. A redirect requires the operator to review
and supply the destination before another run. Do not try other sources or PDF links.
Reuse bounded transport, verified immutable storage, and acquisition history.

The operator reviews retained material before confirming release identity. Extraction
and read-only notification RSS use the existing eligibility and release GUID rules
in [ADR 0014](0014-publish-retained-earnings-through-rss.md). Automatic input-feed
discovery remains governed by [ADR 0017](0017-build-earnings-search-from-feed-updates.md).

<details>
<summary>日本語</summary>

# 運用者が指定した決算 PDF を1件取得する

[#265](https://github.com/9renpoto/lens/issues/265) では、取得先を指定する人が、取得前にその正しさ、
公開元の条件、リリースの公開時期を確認する。手動実行には、有効な登録済み一覧取得先1件と、
確認済み PDF 1件の完全な URL を指定する。Lens は一覧中の PDF リンクを解決し、指定 URL と一致する
リンクが1つの場合にその URL を取得する。照合にはクエリ文字列を含める。掲載順は取得の根拠にしない。
公開元ごとの日付や命名規則に依存せず、[ADR 0007](0007-register-pilot-sources-through-an-interface.md)
に従って一覧からの出典を保持する。

収集の上限内で一覧を読み取れない場合、リンクが存在しないか曖昧な場合、URL が通信ポリシーに
反する場合は停止する。このモードでは確認済み URL を使い、リダイレクトを追跡しない。
リダイレクトが発生した場合は、次の実行前に運用者が遷移先を確認して指定する。別の取得先や
PDF リンクは試行しない。上限付き通信、検証済みの不変ストレージ、取得履歴を再利用する。

運用者は保存資料を確認してからリリース識別を確定する。抽出と読み取り専用の通知用 RSS には
[ADR 0014](0014-publish-retained-earnings-through-rss.md) の既存の公開条件とリリース GUID の規則を適用する。
入力フィードによる自動検知は [ADR 0017](0017-build-earnings-search-from-feed-updates.md) に従う。

</details>
