# Retained earnings RSS

Lens exposes the already retained earnings information for one selected registered
target through RSS 2.0, following [ADR 0014](../adr/0014-publish-retained-earnings-through-rss.md).
Feed retrieval reads existing data and does not collect publisher material,
create candidates, confirm identities or start extraction.

## Subscribe

Reuse the existing target ID and successful retained result. Keep actual target
identities, IDs, URLs and verification output in private, untracked operational
notes. The placeholders below do not identify an operational target.

```sh
BASE_URL=http://127.0.0.1:4000
TARGET_ID=EXISTING_TARGET_UUID
curl --fail-with-body "$BASE_URL/feeds/targets/$TARGET_ID/earnings.rss"
```

Subscribe a conforming RSS consumer to that URL within the existing private/local
access boundary. Configure `LensWeb.Endpoint`'s URL to the address the consumer
can reach: item links use that configured base URL. A port-forward alone does not
rewrite the emitted original links. In development, the configured URL defaults
to `http://127.0.0.1:4000` and follows `PORT` when set; use the same origin for
`BASE_URL`. This feature adds no public exposure or new authentication mechanism.

An existing target with no eligible releases returns an empty RSS channel.
Invalid or unknown target IDs return HTTP 404. Success returns
`application/rss+xml; charset=utf-8` with `Cache-Control: no-store`.

## Item contract

- One item per confirmed release for the target's issuer with a successful
  acquisition and an existing successful extraction. Repeated acquisitions do
  not duplicate items. Unconfirmed originals and other issuers are excluded.
- Reuse the existing per-release text selection: the latest successful extraction
  from the most recently first-acquired original that has successful text. If a
  newer original has no successful text, the existing earlier successful text
  remains selected. The original link always matches the selected extraction.
- `title` is the existing generated display label, not the publisher's original
  title. The channel description identifies these titles as generated labels.
- `description` contains the full stored extracted text as escaped HTML inside
  `<pre>`. Markup from the extracted text remains text. Page-break characters are
  entity-encoded so the RSS remains valid XML. There is no excerpt truncation or
  feed window in this prototype.
- `link` opens `/api/earnings/originals/ORIGINAL_ID`, which reads the retained PDF
  without contacting the publisher.
- `guid` is `urn:uuid:RELEASE_ID` with `isPermaLink="false"`. Shared originals can
  produce distinct release items. A changed selection within the same release
  updates the text and original link under the same GUID, without guaranteeing a
  new-item notification. Repeated reads preserve identity and use stable release-ID
  ordering.
- `pubDate` is emitted only for complete existing publication timestamps, including
  time and timezone. The current selection has no complete publication timestamp,
  so it is omitted; a date-only `published_on` is not converted to midnight, and
  acquisition time is not substituted.

## Verify the existing result

With the new Lens code running and the existing retained data available:

```sh
mix run --no-start scripts/check_earnings_feed.exs "$BASE_URL" "$TARGET_ID"
```

The checker only reads. It parses RSS with `Lens.Ingestion.Parser` and OTP
`:xmerl`, compares repeated reads and GUIDs, compares the complete rendered text
with the existing release-detail API, verifies that each original link matches the
selected extraction and opens its retained PDF. It reports counts and pass/fail
without printing target identities or content. No eligible items is a failure to
complete this observation; report the missing data instead of silently collecting
or creating substitutes. A passing local check demonstrates readable retained
output and usable original links; production rollout and usefulness are separate
observations.

<details>
<summary>日本語</summary>

# 保存済み決算情報のRSS

Lensは[ADR 0014](../adr/0014-publish-retained-earnings-through-rss.md)に従い、
選択した登録済み対象1件の保存済み決算情報をRSS 2.0で取得可能にする。
フィード取得は既存データを読み取り、発行元からの収集、候補作成、識別確定、
本文抽出を起動しない。

## 購読

既存の対象IDと成功した保存済み結果を使う。実際の対象の識別情報、ID、URL、検証出力は
非公開かつGit追跡対象外の運用メモで管理する。以下のプレースホルダーは実運用対象を
識別するものではない。

```sh
BASE_URL=http://127.0.0.1:4000
TARGET_ID=EXISTING_TARGET_UUID
curl --fail-with-body "$BASE_URL/feeds/targets/$TARGET_ID/earnings.rss"
```

既存の非公開・ローカルアクセス境界内で、このURLを標準準拠のRSS購読側へ登録する。
項目リンクには`LensWeb.Endpoint`に設定したベースURLを使うため、購読側から接続可能な
URLを設定する。ポートフォワードだけでは出力する原本リンクは書き換わらない。
開発環境の設定URLは既定で`http://127.0.0.1:4000`となり、`PORT`を設定すると
その値に追従する。`BASE_URL`にも同じオリジンを使う。
この機能は一般公開や新たな認証機構を追加しない。

既存の対象に適格なリリースがなければ空のRSSチャネルを返す。不正・未知の対象IDは
HTTP 404とする。成功時は`application/rss+xml; charset=utf-8`と
`Cache-Control: no-store`を返す。

## 項目の契約

- 対象の発行元に紐付く、成功した取得記録と既存の成功した抽出結果を持つ識別確定済み
  リリースごとに1項目とする。再取得で項目を重複させず、識別未確定の原本や別発行元は
  含めない。
- 既存のリリース単位の本文選択を使う。成功した本文を持つ原本のうち最初の取得が最も
  新しいものから、最新の成功した抽出結果を選ぶ。新しい原本に成功した本文がなければ、
  既存の以前の成功した本文を選択し続ける。原本リンクは選択した抽出結果に必ず対応する。
- `title`は既存の生成済み表示名であり、発行元の原題ではない。チャネルの説明にも
  表題が生成済み表示名であることを記載する。
- `description`は`<pre>`内にHTMLエスケープした保存済み抽出本文の全文を含める。
  抽出本文中のマークアップはテキストとして扱う。改ページ文字は文字参照として出力し、
  RSSを正しいXMLに保つ。このプロトタイプでは抜粋への切り詰めや取得期間の制限は設けない。
- `link`は発行元へ接続せず保存済みPDFを読み取る
  `/api/earnings/originals/ORIGINAL_ID`を開く。
- `guid`は`urn:uuid:RELEASE_ID`、`isPermaLink="false"`とする。原本を共有する
  別リリースは別項目にできる。同じリリース内の選択変更では同じGUIDのまま本文と原本
  リンクを更新し、新着通知は保証しない。反復取得で識別子を維持し、リリースIDで安定した
  順序を使う。
- `pubDate`は時刻・タイムゾーンを含む既存の完全な公表日時がある場合だけ出力する。
  現在の選択には完全な公表日時がないため省略する。日付のみの`published_on`を午前0時へ
  変換せず、取得日時も代用しない。

## 既存の結果の検証

新しいLensコードが動作し、既存の保存済みデータを使える状態で実行する。

```sh
mix run --no-start scripts/check_earnings_feed.exs "$BASE_URL" "$TARGET_ID"
```

検証スクリプトは読み取りのみを行う。`Lens.Ingestion.Parser`とOTPの`:xmerl`でRSSを
解析し、反復取得とGUIDを比較し、表示する全文を既存のリリース詳細APIと照合する。
各原本リンクが選択した抽出結果に対応することを確認し、保存済みPDFを開く。
対象の識別情報や内容を出力せず、件数と成否だけを報告する。適格な項目がなければ
この観測を完了できないため、不足を報告し、黙って追加収集や代替データの作成を行わない。
ローカル検証の成功は保存済み出力を読めることと原本リンクを使えることを示し、
本番への反映や有用性は別の観測として扱う。

</details>
