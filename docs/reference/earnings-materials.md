# Acquiring earnings material

An `earnings_updates` source automatically acquires identifiable material after
new or changed items are detected. Baseline and unchanged items do not acquire
material. Discovery success and material acquisition success are separate:
`Result.materials` holds successful observations and `Result.material_errors`
holds transient failures. Failures are reported through the
[Sentry interface](ingestion-errors.md), without a database error inbox or replay.
Search indexing and PDF text extraction do not run at this stage.

## Configure before enabling

Create or edit the source through `/api/sources`. Keep it disabled while reviewing
publisher conditions and configuring `acquisition_metadata`:

```json
{
  "source": {
    "ingestion_mode": "earnings_updates",
    "endpoint_url": "https://feeds.example.test/earnings.xml",
    "enabled": false,
    "poll_interval_seconds": 300,
    "acquisition_metadata": {
      "material_origins": ["https://publisher.example.test", "https://files.example.test"],
      "html_selector": "article.release"
    }
  }
}
```

`material_origins` must contain 1–16 exact HTTP(S) origins, including non-default
ports. Paths other than `/`, queries, fragments and credentials are rejected.
Every material request and redirect uses this policy; RSSHub's origin grants no
permission to fetch publisher material. Missing or invalid policy causes an error
before any material request. Configure RustFS privately for PDFs using the existing
[storage contract](../deployment.md#earnings-pdf-storage). HTML-only acquisition
does not require a storage client.

`html_selector` is optional and must identify only the detected item's body on
that source. Exactly one element must match. It is an operator-defined association
rule, not automatic confirmation of issuer or release identity. A URL fragment
instead selects exactly one matching element ID. Without either, the fallback
requires one `article`, one matching `h1`, and at most one distinct PDF link;
multiple historical PDFs are ambiguous. Ambiguous pages are not retained or
crawled. Explicit feed PDF references can still succeed independently.

After configuration review, enable the source. Changing a policy does not replay
previously failed items. The first successful feed read still establishes a
baseline without acquiring existing entries.

## Retained representation

HTML is parsed without a browser, JavaScript execution or asset requests. Keep
only text derived from the selected body, its SHA-256, acquisition time,
requested/final URLs, source/feed snapshots and provenance. Provenance includes
link URLs, anchor text, fragments, heading context, element-ID anchors with short
quotes, and an `html-text-v1` extractor marker. HTML response bytes, markup,
stylesheets, scripts and rendered-page snapshots are not retained. Links and
anchors may stop resolving after publisher edits; they are navigation references.

PDFs are detected by explicit feed attachments, item links or scoped page links.
Direct PDF responses also work for URLs without a `.pdf` suffix. Store and verify
bytes in RustFS before recording the original and the material observation.
Identical bytes reuse the existing `earnings_originals` reference; observations
retain their independent source/item/HTTP provenance. No issuer, acquisition
identity or release identity is invented to satisfy the registered collector's
assessment contract. The subscription observation supplies the acquisition facts.

Successful observations are append-only `feed_materials` rows. HTML rows hold
text and no original reference; PDF rows hold an original reference and no byte
copy or extracted text. No source response headers or raw feed HTML are copied
into snapshots. These records support later indexing and revision work and do
not establish semantic completeness or backup guarantees.

## Bounds and handoff

Reuse the streaming HTTP transport: HTML is limited to 2 MiB and PDFs to 20 MiB,
with at most three redirects and no HTTP retries. Known HTML response types use
the 2 MiB cap while streaming; unknown types are bounded by 20 MiB, classified,
and rejected if HTML exceeds 2 MiB. Reject unsupported formats. There are at most
8 distinct material requests per item by default (up to 32 HTTP requests with
redirects). Library callers can set `max_materials` from 1 to the hard cap of 16
(up to 64 HTTP requests). A shared 30-second acquisition deadline covers each feed batch. Exhausted bounds
produce errors, not an assertion that remaining material was acquired. Independent
items are processed and failures stay visible; failed material is not queued.

Retain at most 200 outgoing links, 200 element-ID anchors and 100 heading labels
per HTML observation; excessive link/anchor counts fail extraction. Quotes and
link labels are bounded. Navigation links are recorded, not followed recursively;
only PDFs associated with the selected body become additional acquisition requests.

`Result.materials` returns committed observations. The application also publishes
`{:earnings_material_acquired, material}` on `Lens.PubSub` topic
`earnings_materials` after acquisition. Discovery notifications remain separate;
do not install another acquisition consumer for the same discovery signals.
Handoffs remain best-effort with no recovery queue. Recreate disposable databases
when the current schema fingerprint changes, following [setup](../development.md).

<details>
<summary>日本語</summary>

# 決算資料の取得

`earnings_updates`の取得先は、新着・変更検知後に対応を特定できる資料を自動取得する。
初回基準と変更のない項目は取得しない。更新検知の成功と資料取得の成功を区別し、
`Result.materials`へ成功した観測、`Result.material_errors`へ一時的な失敗を返す。
失敗は[Sentryインターフェース](ingestion-errors.md)へ報告し、DBのエラー管理一覧や再処理は
導入しない。この段階では検索登録とPDF本文抽出は行わない。

## 有効化前の設定

`/api/sources`から取得先を作成・編集する。公開元条件の確認と`acquisition_metadata`の設定中は
無効に保つ。上記のJSON例を使用でき、`material_origins`には非既定ポートを含む正確な
HTTP(S)のoriginを1〜16件設定する。`/`以外のパス、query、fragment、認証情報は拒否する。
すべての資料要求とリダイレクト先へポリシーを適用し、RSSHubのoriginだけでは公開元資料の
取得を許可しない。設定不足・不正では資料要求前にエラーとする。PDF用のRustFSは既存の
[保存契約](../deployment.md#earnings-pdf-storage)に従って非公開設定する。
HTMLだけの取得には保存クライアントは不要。

任意の`html_selector`は、その取得先の検知項目の本文だけを特定するルールとし、
一致する要素は必ず一つとする。運用者が定義する対応付けであり、発行元・リリース識別の
自動確定ではない。URLにfragmentがあれば対応するIDの要素一つを選択する。どちらもない場合は、
単一の`article`、表題と一致する単一の`h1`、異なるPDFリンクが最大一つという条件を必須とする。
過去分の複数PDFがあれば曖昧とする。曖昧なページは保持・巡回せず、フィードに明示された
PDF参照は独立して取得できる。

設定確認後に有効化する。ポリシー変更で過去の失敗項目を再処理しない。
最初の正常なフィード取得では引き続き基準だけを作り、既存項目を取得しない。

## 保持する表現

HTMLはブラウザ・JavaScript実行・付属資源取得なしで解析する。選択した本文からの抽出テキスト、
SHA-256、取得日時、取得前後のURL、取得先・項目のsnapshot、出典情報だけを保持する。
出典にはリンクURL・アンカーテキスト・fragment・見出しの文脈・短い引用を伴う要素IDアンカー・
`html-text-v1`の抽出器識別を含める。HTML応答バイト列・マークアップ・スタイルシート・script・
レンダリング結果は保持しない。リンクとアンカーは移動のための参照であり、公開元編集後に
参照できなくなる場合がある。

PDFはフィードの明示的な添付・項目リンク・選択本文内のリンクから特定する。`.pdf`で終わらない
URLでも、PDF応答を直接取得できる。RustFSへバイト列を保存・検証してから原本と資料観測を記録する。
同じバイト列は既存の`earnings_originals`参照を再利用し、観測ごとに取得先・項目・HTTP来歴を保つ。
登録済みCollectorの判定契約を満たすために発行元・取得識別・リリース識別を捏造しない。
購読の資料観測自体が取得事実を記録する。

成功した観測は追記専用の`feed_materials`行となる。HTML行は本文を保持して原本参照を持たず、
PDF行は原本参照を保持してバイト列のコピーや抽出本文を持たない。応答ヘッダーと生のフィードHTMLは
snapshotへコピーしない。これらは後続の検索登録・改訂管理に使用し、内容の完全性やバックアップを
保証しない。

## 上限と受け渡し

既存のストリーミングHTTPを再利用し、HTMLは2 MiB、PDFは20 MiB、リダイレクトは最大3回、
HTTP再試行なしとする。HTMLと分かる応答形式は転送中に2 MiB上限を適用する。形式不明の応答も
20 MiBで制限し、分類後にHTMLが2 MiBを超えていれば拒否する。未対応形式は拒否する。
1項目の異なる資料要求は既定で最大8件（リダイレクト込みHTTP要求は最大32件）とする。
ライブラリ呼び出しでは`max_materials`を1〜上限16件（HTTP要求は最大64件）に設定できる。
フィードbatch全体の取得は30秒の共通期限とする。上限超過は残りの取得完了ではなくエラーにする。独立した項目の処理を
進め、失敗を可視化し、失敗資料はキューに入れない。

HTML観測ごとにリンク200件・要素IDアンカー200件・見出し100件を上限とし、リンク・アンカーの
超過は抽出失敗にする。引用とリンク文字列も長さを制限する。移動用リンクは記録だけ行って再帰的に
巡回せず、選択本文に対応するPDFだけを追加取得する。

`Result.materials`はコミット済み観測を返す。取得後には`Lens.PubSub`の`earnings_materials`
トピックへ`{:earnings_material_acquired, material}`も配信する。更新検知の通知とは分離し、
同じ検知情報へ別の取得処理を二重接続しない。受け渡しは引き続きbest-effortで復旧キューを持たない。
現行スキーマのfingerprint変更時は[セットアップ](../development.md)に従い破棄可能DBを再作成する。

</details>
