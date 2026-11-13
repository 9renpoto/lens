# Service RSS feed

Lens serves one read-only RSS 2.0 feed for acquired information and confirmed
earnings releases under [ADR 0014](../adr/0014-publish-retained-earnings-through-rss.md).

## Subscribe

Register the service URL with an RSS consumer inside the existing private access
boundary. Use the Lens base URL that the consumer can reach. Configure the
application endpoint URL accordingly because Lens uses it in links to retained
originals.

```sh
BASE_URL=http://127.0.0.1:4000
curl --fail-with-body "$BASE_URL/feeds/earnings.rss"
```

The endpoint returns `application/rss+xml; charset=utf-8` and `Cache-Control: no-store`.
A service with no eligible data returns a valid empty channel. Reading the feed
only reads retained data. The consumer handles polling, notifications, and read
state.

The service URL replaces the target-specific RSS URL. Register a new subscription
at the service URL. The feed contract provides no subscription or notification
history migration.

## Publication

- **Input updates.** Configure a feed source as described in [material acquisition](earnings-materials.md).
  Supply an `html_selector` for the intended HTML body. A new or changed input
  item publishes after the configured selector matches one element and yields
  non-empty extracted text. The item contains the input title, extracted text,
  and source URL. Missing or ambiguous evidence leaves that version out of the
  feed. Each successful update gets its own GUID, including a changed input
  whose extracted text is identical. Earlier successful updates remain readable.
- **Confirmed releases.** A confirmed release with a successful acquisition and
  extraction appears with its generated title, selected full text, corresponding
  retained PDF link, and existing release GUID. A newer selected extraction can
  update the item under the same GUID.
- All GUIDs are opaque and stable across repeated reads. Lens sets `pubDate`
  when a complete publisher publication timestamp is available. The feed
  preserves extracted text using RSS and HTML escaping.

Keep live source configurations, identifiers, and verification output in private
operational records.

## Check a populated feed

Run the read-only checker from the source checkout:

```sh
MIX_ENV=test mix run --no-start scripts/check_earnings_feed.exs "$BASE_URL"
```

The checker verifies RSS parsing, unique GUIDs, and stable repeated reads. It
checks retained text through the relevant Lens detail API and verifies retained
PDF links for release items.

## Reproduce scheduled notification delivery

From a source checkout with dependencies installed and a disposable local
PostgreSQL test database configured, run:

```sh
mix test test/lens/ingestion/rss_notification_test.exs
```

The test uses one loopback HTTP source and establishes an empty baseline. The
Lens scheduler polls the source after a synthetic article is added. A test
consumer reads the Lens RSS endpoint and sends one HTTP notification per unseen
GUID to a loopback receiver. The receiver checks the delivered text and URL
against the retained evidence API. After another item appears whose linked page
lacks the required article, the feed still contains only the successful item and
the receiver gets no additional notification.

<details>
<summary>日本語</summary>

# サービス共通 RSS

[ADR 0014](../adr/0014-publish-retained-earnings-through-rss.md) に従い、Lens は
取得した情報と識別確定済みの決算リリースを1つの読み取り専用 RSS 2.0 フィードで提供する。

## 購読

既存の非公開アクセス境界内で、サービス URL を RSS 購読側に登録する。購読側から
到達できる Lens のベース URL を使う。保存原本へのリンクにはアプリのエンドポイント URL が
使われるため、購読側から到達できるように設定する。

```sh
BASE_URL=http://127.0.0.1:4000
curl --fail-with-body "$BASE_URL/feeds/earnings.rss"
```

応答は `application/rss+xml; charset=utf-8` と `Cache-Control: no-store` を返す。
対象データがない場合も、有効な空チャネルを返す。フィード取得では保存済みデータを読み、
定期確認、通知、既読状態は購読側が管理する。

サービス URL は対象別 RSS URL を置き換える。サービス URL で新規に購読する。
購読設定や通知履歴の移行処理は提供しない。

## 掲載

- **入力更新**。[資料取得の手順](earnings-materials.md) に従ってフィード取得先を設定し、
  目的の HTML 本文に `html_selector` を指定する。新着または変更された入力項目は、指定の
  セレクタが1要素に一致し、空でない本文を抽出できた場合に掲載する。項目には入力の表題、
  抽出本文、出典 URL を含める。根拠がないか曖昧な版は掲載しない。抽出本文が同じでも入力に
  変更があれば、成功した更新ごとに GUID を割り当てる。以前の成功版も引き続き読める。
- **確定済みリリース**。取得・抽出に成功した識別確定済みリリースは、生成済み表題、
  選択した抽出本文の全文、対応する保存 PDF のリンク、既存のリリース GUID とともに掲載する。
  新しい抽出結果が選ばれると、同じ GUID のまま項目の内容を更新できる。
- GUID は識別子として扱い、繰り返し読み取っても維持する。発行元の公表日時が揃う場合は
  `pubDate` を設定する。RSS と HTML のエスケープで抽出本文を保持する。

実ソースの設定、識別子、検証結果は非公開の運用記録に置く。

## 項目があるフィードを確認する

ソースのチェックアウトから、読み取り専用の確認スクリプトを実行する。

```sh
MIX_ENV=test mix run --no-start scripts/check_earnings_feed.exs "$BASE_URL"
```

スクリプトは RSS のパース、GUID の一意性、繰り返し読み取った際の安定性を確認する。
対応する Lens の詳細 API で保存本文を照合し、リリース項目の保存 PDF リンクを検証する。

## 定期取得から通知の着信までを再現する

依存関係を導入し、使い捨てのローカル PostgreSQL テストデータベースを設定した
ソースチェックアウトで実行する。

```sh
mix test test/lens/ingestion/rss_notification_test.exs
```

ループバック HTTP の取得先1件で空の初回基準を確立する。合成記事の追加後に Lens の
スケジューラが取得先をポーリングする。テスト用購読側は Lens の RSS エンドポイントを読み、
未受信の GUID ごとにループバックの受信先へ HTTP 通知を1件送る。着信した本文と URL を
保存済みの根拠 API と照合する。必要な記事本文を欠くページを指す項目を追加しても、
出力 RSS には成功した項目だけが残り、追加の通知は届かない。

</details>
