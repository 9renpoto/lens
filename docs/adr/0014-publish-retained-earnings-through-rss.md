---
status: accepted
---

# Publish retained earnings information through RSS

Expose the already collected earnings information for the selected issuer through
one local RSS feed so the operator can read the stored result before deciding what
would make it more useful. Use existing successful extractions and retained
originals. The release boundary and implementation work belong in
[#185](https://github.com/9renpoto/lens/issues/185) and
[#186](https://github.com/9renpoto/lens/issues/186).

Publish one item per retained earnings document whose successful acquisition
is already linked to a confirmed release for that issuer and which has an existing
successful extraction. Include that release's existing generated title,
the full extracted text and a link to the corresponding retained original PDF.
Unconfirmed originals are outside feed eligibility; feed retrieval does not
confirm release identities or invent fallback titles. These conditions reuse
existing identity and extraction data without editorial selection for usefulness.
The generated title is a display label, not a claim to reproduce the publisher's
original title. Preserve the stored extracted text as readable text through RSS
escaping, without adding a summary or interpretation. Preserve stable item
identity across repeated reads.

Set item `pubDate` only when existing publisher metadata specifies the publication
date, time and timezone, allowing an [RSS 2.0](https://www.rssboard.org/rss-2-0-11)
RFC 822 date-time without inventing missing components. Omit this optional element
for missing or date-only metadata such as `published_on`. Do not infer midnight
or a timezone, or substitute acquisition time.

Feed retrieval reads retained data without fetching publisher material or
starting extraction. Keep the feed and original links within the application's
existing private/local access boundary. The consumer must be able to reach both
Lens and the retained-original endpoint; this decision does not introduce public
internet exposure or new authentication mechanisms.

Consumer verification checks that the stored text is readable, the original link
opens the corresponding retained PDF, and repeated reads preserve item identity.
Usefulness can be discussed after reading the actual result; it is not a release
success criterion. Manual candidate authoring or editorial selection, new
collection or extraction, summaries, interpretations, comparisons, a new reading
UI and downstream notification/read-state management are outside this boundary.

## Replacement of the manual-registration decision

The agreed revision of 2026-10-23 replaces this record's earlier decision to
register manually authored investigation candidates. Human-authored input can
bypass the collected information entirely and cannot establish that Lens makes
its existing collection readable. Reusing retained material makes that result
observable before investing in ways to add value. The broader investigation-
candidate concept remains a separate product hypothesis.

<details>
<summary>日本語</summary>

# 保存済みの決算情報をRSSで公開する

すでに収集した検証対象企業の決算情報をローカル単一RSSフィードで取得可能にし、
運用者が保存済みの結果を読んでから、何を改善すると役立つかを判断できるようにする。
既存の成功した抽出結果と保存原本を使う。リリース境界と実装作業は
[#185](https://github.com/9renpoto/lens/issues/185)と
[#186](https://github.com/9renpoto/lens/issues/186)で管理する。

成功した取得記録が識別確定済みの検証対象企業のリリースに紐付いており、既存の
成功した抽出結果を持つ保存済み決算資料ごとに項目を作る。そのリリースの既存の生成済み
表題、抽出本文の全文、対応する保存原本PDFへのリンクを含める。識別未確定の原本は
フィードの対象外とし、フィード取得時にリリース識別を確定したり代替表題を作り出したり
しない。これらの条件は既存の識別・抽出データを使うものであり、有用性による公開対象の
選別は行わない。生成済み表題は表示用の名前であり、発行元の原題を再現したものとは
扱わない。RSSのエスケープを通じて保存済み抽出本文を読めるテキストとして維持し、
要約や解釈は追加しない。反復取得を通じて項目識別子を維持する。

項目の`pubDate`は、発行元の公表日・時刻・タイムゾーンが既存データにあり、
不足する要素を作り出さずに[RSS 2.0](https://www.rssboard.org/rss-2-0-11)の
RFC 822日時として表現できる場合だけ出力する。情報がない場合や`published_on`のように
日付だけの場合、この任意要素は省略する。午前0時やタイムゾーンを推測したり、
取得日時で代用したりしない。

フィード取得は保存済みデータを読み取り、発行元からの取得や本文抽出を起動しない。
フィードと原本リンクはアプリの既存の非公開・ローカルアクセス境界内に置く。
購読側はLensと保存原本エンドポイントの両方へ接続できる必要があり、この判断で
インターネットへの一般公開や新しい認証機構は導入しない。

購読側での検証では、保存済み本文を読めること、原本リンクから対応する保存済みPDFを
開けること、反復取得で項目識別子を維持することを確認する。有用性は実際の結果を
読んだ後に議論できるが、リリースの成功条件にはしない。手動候補作成や人間による
公開対象の選別、新規収集・抽出、要約・解釈・比較、閲覧UIの新設、後続の通知配信・
既読状態の管理は、この境界に含めない。

## 手動登録の判断の置き換え

2026-10-23に合意した改訂により、この記録の従来の手動調査候補登録の判断を置き換える。
人間が作成した入力は収集済み情報を使わずに成立するため、Lensの既存の収集結果を
読めることを確かめられない。保存済み資料の再利用により、価値の付加方法へ投資する前に
その結果を観測可能にする。より広い調査候補の概念は、別のプロダクト仮説として維持する。

</details>
