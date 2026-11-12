---
status: accepted
---

# Publish acquired earnings information through one service RSS feed

Expose one read-only RSS 2.0 feed per Lens service. All sources share the same
subscription URL. A single feed lets an operator receive acquired information
quickly and review the evidence afterward. Consider splitting the feed when
the volume or variety of information warrants it.

## Automatic publication

Use the input feed and material acquisition path in
[ADR 0017](0017-build-earnings-search-from-feed-updates.md). Start with one
registered feed source whose `html_selector` identifies the intended HTML body.
Publish one item for each new or changed input item after acquisition and
extraction yield non-empty text from the one element matching that selector.
A missing or ambiguous match, a failed acquisition, or missing required text
is a processing failure under ADR 0017 and produces no RSS item. Human review
takes place after notification. Evaluating the usefulness of the evidence is a
separate activity.

Include the input item's title, the extracted text, and the source URL for the
extracted body. Preserve readable text through RSS escaping. Each successfully
published input update has its own stable GUID. Each detected change that meets
the publication conditions produces a new item and GUID even when the extracted
text and source URL are unchanged. Repeated polls of unchanged input and reads
of the output feed preserve the published items and GUIDs. Earlier successful
items remain available when later versions succeed or fail.

## Retained releases

Include confirmed earnings releases with successful acquisitions and
extractions in the same feed. Each release keeps its generated title, selected
full extracted text, link to the corresponding retained PDF, and
`urn:uuid:<release-id>` GUID. Selecting another successful extraction for the
same release updates its content and original link under the same GUID.
An item from an input update and an item from a confirmed release may both be
present when they refer to the same material.

## Publication and replacement boundary

Set `pubDate` only when publisher metadata supplies the date, time, and timezone
required by [RSS 2.0](https://www.rssboard.org/rss-2-0-11). Use opaque GUIDs with
`isPermaLink="false"`. Reading the feed uses retained data. Acquisition and
extraction run independently of feed reads. Keep the feed and retained originals
inside the existing private access boundary. Consumers own polling,
notification delivery, and read state.

Replace the target-specific RSS implementation with the service feed. Consumers
use the service URL for new subscriptions. The replacement ships without an
endpoint compatibility layer or a migration for old subscriptions, published
items, or consumer notification history. Reuse existing retained release data
where compatible. If a breaking change requires a reset of disposable data,
follow [ADR 0010](0010-defer-backups-for-disposable-development-data.md). Affected
disposable data may be truncated when the existing schema remains usable.

<details>
<summary>日本語</summary>

# 取得した決算情報をサービス共通の RSS で公開する

Lens のサービスごとに、読み取り専用の RSS 2.0 フィードを1つ提供する。すべての取得先で
購読 URL を共有する。単一のフィードにすることで、運用者は取得した情報を早く受け取り、
その後に根拠を確認できる。情報の量や種類が増え、必要になった段階でフィードの分割を検討する。

## 自動掲載

[ADR 0017](0017-build-earnings-search-from-feed-updates.md) の入力フィードと資料取得の
経路を使う。最初は、目的の HTML 本文を `html_selector` で指定した登録済みフィード取得先1件を扱う。
入力項目の新着・変更ごとに、取得・抽出によって指定セレクタに一致する1要素から空でない本文を
取得できた場合に、出力項目を1件作る。一致なし、複数一致、取得失敗、必要な本文の欠落は
ADR 0017 に従って処理失敗として扱い、RSS 項目を作らない。人によるレビューは通知後に行う。
根拠の有用性の評価は別途扱う。

入力項目の表題、抽出本文、その本文の出典 URL を含める。RSS のエスケープによって本文を
読める状態に保つ。掲載に成功した入力更新ごとに、固有で安定した GUID を割り当てる。
入力フィード上で検知した変更が掲載条件を満たした場合は、抽出本文と出典 URL が同じでも、
新しい項目と GUID を作る。変更のない入力の再取得や出力 RSS の再読では、掲載済みの項目と GUID を維持する。
後の版の処理結果にかかわらず、以前に掲載に成功した項目は残す。

## 保存済みリリース

取得と抽出に成功した識別確定済みの決算リリースも同じフィードに含める。リリースごとに、
既存の生成済み表題、選択した抽出本文の全文、対応する保存原本 PDF へのリンク、
`urn:uuid:<release-id>` の GUID を維持する。同じリリースで別の成功抽出結果を選択した場合は、
同じ GUID のまま本文と原本リンクを更新する。同じ資料を指す入力更新の項目と確定済み
リリースの項目が、両方掲載される場合がある。

## 公開と置き換えの境界

`pubDate` は、発行元のメタデータに [RSS 2.0](https://www.rssboard.org/rss-2-0-11) が
要求する日付・時刻・タイムゾーンが揃う場合だけ設定する。GUID は識別子として扱い、
`isPermaLink="false"` を設定する。フィード取得では保存済みデータを読む。資料の取得・抽出は
フィードの読み取りから独立して実行する。フィードと保存原本は既存の非公開のアクセス境界内に置く。
購読側が定期確認、通知配信、既読状態を管理する。

対象別の RSS 実装をサービス共通フィードに置き換える。購読側はサービス URL を使って新規に
購読する。旧エンドポイントの互換層や、旧購読・掲載項目・通知履歴の移行処理は設けない。
互換性のある保存済みリリースデータは再利用する。破壊的変更で破棄可能なデータの初期化が
必要な場合は [ADR 0010](0010-defer-backups-for-disposable-development-data.md) に従う。
現行スキーマを引き続き使える場合は、影響する破棄可能なデータを `TRUNCATE` してよい。

</details>
