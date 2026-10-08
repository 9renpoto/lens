# Registered earnings candidate collection

`Lens.Earnings.Collector.run/1` performs one sequential, bounded run over enabled database-backed earnings sources. Target `active` does not control source enablement. Run it manually with:

```sh
mix run -e 'IO.inspect(Lens.Earnings.Collector.run())'
```

Registration and acquisition conditions are described in [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md). The default URL policy accepts absolute HTTP(S) URLs without credentials within 4096 bytes, including external document hosts; it is not a network-address restriction. Deploy within the existing private operator access boundary. Callers can supply `allowed_url?: fn url -> ... end` to restrict destinations. The same policy applies to initial requests and every redirect. Discovery ignores credential-bearing links and follows actual PDF anchors, resolving relative links against the final listing response URL.

One run shares `RunBudget` limits: 24 HTTP requests including redirects, 8 operations and a 120-second deadline by default. Override `max_requests`, `max_operations` and `timeout_ms` within the existing run-budget bounds. Each request retains the existing 20-second timeout, three-redirect cap, 2 MiB listing cap and 20 MiB PDF cap. The run stops before exceeding its budget; it does not queue unfinished work or install a daily scheduler. Every invocation discovers the current listing again and acquires its PDF links in document order until the budget is exhausted. It does not yet select the latest reporting release, track new listings or guarantee fairness across runs.

The return value is `{:ok, %{checks: checks, errors: errors, budget: budget, stopped: reason}}`; invalid budgets return `{:error, :invalid_budget}`. Checks are returned in operation order. HTTP failures are recorded and do not block other links or sources. Discovery failures appear in `errors`; budget exhaustion appears in `stopped`. Persistence failure stops the run with `:persistence_failed` rather than continuing acquisition without durable history. No automatic HTTP retries are added.

Every persisted check retains source ID, target ID and the registered listing URL in `metadata`. PDF checks also retain the listing check ID, final listing response URL, observed href, resolved document URL, anchor text and headings. Listing checks retain their final response URL. Configuration edits or disablement do not rewrite these snapshots. Successful PDF checks reference immutable, byte-deduplicated originals through an acquisition with no release identity. Repeated runs create distinct checks and acquisition attempts while identical bytes reuse an original. Started PDF failures retain their failure acquisition; 304 responses and failures before a request do not fabricate acquisitions.

This is the candidate acquisition boundary for #125. #126 consumes acquisition provenance and records assessments separately; #127 supplies release classification and identity. Collection does not invoke extraction, classification or operator adoption. Daily operation, release-aware selection and end-to-end deployment verification remain follow-up work under #68 and its verification issues.

<details>
<summary>日本語</summary>

# 登録済み決算資料候補の収集

`Lens.Earnings.Collector.run/1` は、有効なDB管理の決算取得先を逐次処理する、上限付きの1回の実行を提供する。対象の `active` は取得先の有効状態を制御しない。手動実行は次のとおり。

```sh
mix run -e 'IO.inspect(Lens.Earnings.Collector.run())'
```

登録と取得条件は [ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md) に記載する。既定のURLポリシーは、認証情報を含まない4096バイト以内の絶対HTTP(S) URLを外部資料ホストも含めて許可し、ネットワークアドレスの制限は行わない。既存の非公開の運用者アクセス境界内で配置する。呼び出し側は `allowed_url?: fn url -> ... end` で取得先を制限できる。同じポリシーを最初のリクエストと各リダイレクト先に適用する。発見処理は認証情報を含むリンクを無視し、実際のPDFリンクを追跡して、相対リンクを一覧応答の最終URLから解決する。

1回の実行は `RunBudget` の上限を共有する。既定はリダイレクトを含む24リクエスト、8操作、120秒の期限。既存の実行上限内で `max_requests`、`max_operations`、`timeout_ms` を指定できる。各リクエストは既存の20秒タイムアウト、3回のリダイレクト上限、一覧2 MiB・PDF 20 MiBの上限を維持する。上限超過前に停止し、未完了作業のキューや日次スケジューラーは追加しない。各実行で現在の一覧を再発見し、上限まで資料の掲載順にPDFリンクを取得する。最新の決算回の選択、新規掲載の追跡、実行間の公平性はまだ提供しない。

戻り値は `{:ok, %{checks: checks, errors: errors, budget: budget, stopped: reason}}`。不正な上限は `{:error, :invalid_budget}` を返す。確認記録は操作順に返す。HTTP失敗は記録し、ほかのリンクや取得先を止めない。発見失敗は `errors`、上限到達は `stopped` に残す。永続化失敗は履歴を保存できないまま取得を続けず、`:persistence_failed` で実行を止める。自動HTTP再試行は追加しない。

各確認記録の `metadata` は取得先ID、対象ID、登録一覧URLを保持する。PDF確認は一覧確認ID、一覧応答の最終URL、観測したhref、解決済み資料URL、リンク文字列、見出しも保持する。一覧確認は応答の最終URLを保持する。設定変更や無効化でこれらの記録を書き換えない。成功PDF確認は、短信識別を持たない取得記録から、不変でバイト単位の重複を排除した原本を参照する。再実行は別の確認・取得試行を作るが、同一バイト列は原本を再利用する。リクエスト開始後のPDF失敗は失敗取得記録を保持し、304応答と送信前の失敗は取得記録を捏造しない。

これは #125 の候補取得境界である。#126 は取得の出典を利用し、判定を独立して記録する。#127 は短信の分類と識別を提供する。収集は抽出・分類・運用者による採用を呼び出さない。日次運用、決算回に基づく選択、デプロイ先での一連の検証は #68 と関連検証Issueの後続作業に残る。

</details>
