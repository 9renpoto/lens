# Earnings-search value validation

This procedure supports one reviewable v0.2 slice: register one issuer's
official earnings listing, make one operator-approved bounded manual
collection, extract and search the latest ordinary earnings release available
at collection time, then open the retained original PDF and compare it with the
search result. Use an internal, non-commercial development or test environment
whose data is explicitly disposable under [ADR 0010](../adr/0010-defer-backups-for-disposable-development-data.md).

Before the pilot, the operator selects an issuer and identifies its current
official listing and newest ordinary earnings release.

## Before enabling the source

The operator must read the selected publisher's current site terms and decide
whether the intended acquisition is allowed. Keep this pilot internal and
non-commercial, perform one manual bounded run, and do not schedule recurring
collection or redistribute the PDF. Record the listing URL, the conditions
reviewed, and the run time in a private operational note. The application does
not interpret or approve publisher terms.

## Register and collect

Use the existing private operator API. Reuse the target for the selected issuer
if present; otherwise create one. Replace the placeholders below with values
appropriate for the private pilot.

```sh
curl http://127.0.0.1:4000/api/targets

curl -X POST http://127.0.0.1:4000/api/targets \
  -H 'content-type: application/json' \
  -d '{"target":{"security_code":"SECURITY_CODE","market":"MARKET","display_name":"ISSUER_NAME","sector":"SECTOR","tags":[]}}'
```

Register the selected issuer's official listing disabled, then enable it only
after the operator has reviewed the terms. Substitute the private pilot's
listing URL and target ID for `LISTING_URL` and `TARGET_ID`.

```sh
curl -X POST http://127.0.0.1:4000/api/targets/TARGET_ID/earnings-sources \
  -H 'content-type: application/json' \
  -d '{"source":{"listing_url":"LISTING_URL","enabled":false}}'

curl -X PATCH http://127.0.0.1:4000/api/targets/TARGET_ID/earnings-sources/SOURCE_ID \
  -H 'content-type: application/json' \
  -d '{"source":{"enabled":true}}'
```

`Collector.run/1` visits every enabled registered earnings source across all
targets. Before the manual run, inspect every target's source list and ensure
only the intended source is enabled. Configure the RustFS runtime variables required by
[candidate collection](earnings-collector.md), and apply migrations first.
Verify the live listing before proceeding. Two operations cap this run at the
listing request and its first PDF link:

```sh
mix run -e 'IO.inspect(Lens.Earnings.Collector.run(max_operations: 2))'
```

Check the returned listing/PDF checks and confirm that the PDF is a successful
acquisition for the newest ordinary earnings release shown on the official
listing. If the first link is not that release, stop and record the workflow
gap; do not run a broader crawl for this pilot. The returned PDF check's
`acquisition_id` is the acquisition row's primary key. Load that row to obtain
the provenance `acquisition_id` needed by `confirm_identity/2` and the retained
`original_id` needed for extraction:

```sh
mix run -e 'a = Lens.Repo.get!(Lens.Earnings.Acquisition, "ACQUISITION_ROW_ID"); IO.inspect(%{acquisition_id: a.acquisition_id, original_id: a.original_id})'
mix lens.earnings.extract --original ORIGINAL_ID
```

After reviewing the extracted text against the PDF's title and issuer
identifier, confirm the identity from observed PDF content. Use the provenance
`acquisition_id` printed from the loaded row. Replace the sample
period and fiscal year end below with values printed in the latest PDF:

```sh
mix run -e 'IO.inspect(Lens.Earnings.confirm_identity("PROVENANCE_ACQUISITION_ID", %{fiscal_year_end: Date.from_iso8601!("FISCAL_YEAR_END"), period: "PERIOD", category: "earnings_release"}))'
```

`confirm_identity/2` is a library operation invoked through `mix run`; this
pilot does not add a pending-review API or a dedicated one-command workflow.
Then use the existing Japanese search endpoint and the exact-original endpoint:

```sh
curl --get http://127.0.0.1:4000/api/search \
  --data-urlencode 'q=ISSUER_NAME FISCAL_YEAR PERIOD earnings release'

curl -o original.pdf \
  http://127.0.0.1:4000/api/earnings/originals/ORIGINAL_ID
```

Use the observed issuer, period, and fiscal year in the query. Open the
retrieved PDF, compare its issuer, period, title,
and relevant content with the result, and discuss usefulness and any mismatch
or workflow gap in the review. Mismatches are observations, not automatic
release failures; no numeric precision threshold or standardized value-review
report is required. The acquisition URL, time and stored bytes remain part of
the existing operational provenance.

The v0.2 reviewable checkpoint is complete when the operator has run this
single-company flow through search and original comparison and discussed the
result. The outcome may inform v0.3 scope even when the result is mismatched or
not useful. Search UI, multiple companies, recurring collection, presentation
classification, pending-case/operator-decision APIs, and detailed restart,
failure and backup/restore verification remain follow-up work.

<details>
<summary>日本語</summary>

# 決算検索の価値検証

この手順は、レビュー可能なv0.2の縦切り1件を実施する。発行元1社の公式決算一覧を登録し、運用者が許容した上限付きの手動収集を1回行い、収集時点で最新の通常決算短信を抽出・検索した後、保存した原本PDFを開いて検索結果と照合する。データを明示的に破棄可能とした開発・テスト環境で実施する。[ADR 0010](../adr/0010-defer-backups-for-disposable-development-data.md)を参照。

パイロット前に運用者が発行元を選び、現在の公式一覧と最新の通常決算短信を特定する。

## 取得先を有効にする前に

運用者は選定した発行元の最新のサイト利用条件を読み、予定する取得が許容されるかを判断する。このパイロットは組織内の非商用利用に限定し、上限付き手動実行を1回だけ行う。定期実行やPDFの再配布はしない。非公開の運用メモに取得元一覧URL、確認した条件、実行日時を記録する。アプリは発行元条件を解釈・承認しない。

## 登録と収集

既存の非公開運用者APIを使う。選定した発行元の対象が既にあれば再利用し、なければ作成する。以下の値は非公開パイロットに合わせて置き換える。

```sh
curl http://127.0.0.1:4000/api/targets

curl -X POST http://127.0.0.1:4000/api/targets \
  -H 'content-type: application/json' \
  -d '{"target":{"security_code":"SECURITY_CODE","market":"MARKET","display_name":"ISSUER_NAME","sector":"SECTOR","tags":[]}}'
```

選定した発行元の公式一覧を無効状態で登録し、運用者が条件を確認した後にのみ有効化する。`LISTING_URL`と`TARGET_ID`は非公開パイロット用の値に置き換える。

```sh
curl -X POST http://127.0.0.1:4000/api/targets/TARGET_ID/earnings-sources \
  -H 'content-type: application/json' \
  -d '{"source":{"listing_url":"LISTING_URL","enabled":false}}'

curl -X PATCH http://127.0.0.1:4000/api/targets/TARGET_ID/earnings-sources/SOURCE_ID \
  -H 'content-type: application/json' \
  -d '{"source":{"enabled":true}}'
```

`Collector.run/1`は、全対象に登録された有効な決算取得先すべてを処理する。手動実行前に全対象の取得先一覧を確認し、対象の1件だけが有効であることを確認する。[候補収集](earnings-collector.md)が必要とするRustFSランタイム変数を設定し、先にマイグレーションを適用する。実行前に公式一覧を確認する。操作数を2にすると、一覧取得と先頭PDFリンクの取得までに上限を設定できる。

```sh
mix run -e 'IO.inspect(Lens.Earnings.Collector.run(max_operations: 2))'
```

戻り値の一覧・PDF確認記録を見て、最新の通常短信PDFが取得成功したことを確認する。先頭リンクが該当資料でなければ停止し、この手順上の不足を記録する。このパイロットで広いクロールを実行しない。PDF確認記録の`acquisition_id`は取得行の主キーである。その行を読み込み、`confirm_identity/2`に必要な出典用`acquisition_id`と抽出に必要な保存原本IDを確認する。

```sh
mix run -e 'a = Lens.Repo.get!(Lens.Earnings.Acquisition, "ACQUISITION_ROW_ID"); IO.inspect(%{acquisition_id: a.acquisition_id, original_id: a.original_id})'
mix lens.earnings.extract --original ORIGINAL_ID
```

抽出本文をPDFの表題・発行元識別子と見比べた後、原本上で確認した内容に基づき短信識別を確定する。読み込んだ取得行から出典用`acquisition_id`を使う。期間と決算期末は、実際の最新PDFに記載された値へ置き換える。

```sh
mix run -e 'IO.inspect(Lens.Earnings.confirm_identity("PROVENANCE_ACQUISITION_ID", %{fiscal_year_end: Date.from_iso8601!("FISCAL_YEAR_END"), period: "PERIOD", category: "earnings_release"}))'
```

`confirm_identity/2`は`mix run`から呼び出すライブラリ関数であり、このパイロットでは確認待ちAPIや一括実行CLIを追加しない。その後、既存の日本語検索APIと原本取得APIを使う。

```sh
curl --get http://127.0.0.1:4000/api/search \
  --data-urlencode 'q=ISSUER_NAME FISCAL_YEAR PERIOD 決算短信'

curl -o original.pdf \
  http://127.0.0.1:4000/api/earnings/originals/ORIGINAL_ID
```

観察した発行元名・対象期間・決算期をクエリに使う。取得したPDFを開き、発行元・対象期間・表題・関連内容を検索結果と照合して、有用性や不一致・作業上の不足をレビューで議論する。不一致は観測結果であり、自動的なリリース失敗とはしない。数値の精度基準や定型の価値検証報告は求めない。取得元URL・日時・保存バイト列は既存の運用履歴に保持される。

検索と原本照合まで1社の一連のフローを実行し、その結果を議論できればv0.2のレビュー可能な区切りとする。一致しない場合や有用でない場合も、その結果をv0.3のスコープ判断に使う。検索UI、複数社、定期収集、説明会資料の判定、確認待ち・運用者判断API、詳細な再起動・失敗・バックアップ/復元検証は後続作業とする。

</details>
