# Next minor release planning

Status: the agreed plan is published to the [v0.2 milestone](https://github.com/9renpoto/lens/milestone/2)
and [release tracker #68](https://github.com/9renpoto/lens/issues/68). The
latest base, `main` at `5bdd33b` (2026-10-04), includes preservation and
extraction foundations plus bounded discovery/HTTP components. Source access
conditions, integrated daily/manual collection, complete operator API/CLI
access, and database restore evidence remain in the tracker.

## Agreed direction

- Prioritize collection and preservation foundations while identifying candidate
  sources and decomposing their requirements.
- Limit this release to a small earnings-information pilot that can collect,
  preserve original material, regenerate text, and search it. Saved searches
  and continuous new-publication monitoring belong in dependent follow-up issues.
  Other collection candidates are deferred from this release's working scope.
- The first collection candidate is earnings information from companies with a
  large influence on the Nikkei Stock Average. Fix the initial three companies
  using the top three index weights at a recorded reference date, rather than
  dynamically changing the company set. See the
  [source evaluation](earnings-source-evaluation.md#fixed-pilot-company-set).
- Limit initial material to Japanese earnings-release PDFs. Start
  with the latest release for each company at collection initialization, then
  collect newly listed releases. Presentation materials, structured financial
  data, and bulk historical acquisition are follow-up work.
- Investigate company official IR first and use acquisition routes whose
  conditions fit the pilot. A paid TDnet API remains an alternative; an API
  subscription is not a prerequisite of the initial plan.
- The initial monitoring meaning is newly published information matching saved
  searches. Revision detection and period-over-period financial comparison are
  separate future questions, not part of that initial monitoring definition.
- Preserve official original material, acquisition URL, and acquisition time;
  searchable text must be regenerable from retained material. See
  [ADR 0001](adr/0001-preserve-original-material-for-reprocessing.md).
- Preserve distinct acquired originals without overwriting older bytes, including
  changes at the same URL. Reacquiring the same bytes adds acquisition history
  without duplicating original storage. Semantic revision comparison is deferred.
- Keep acquired originals even when text extraction fails. Record those outcomes
  separately and support extraction retries from retained originals. OCR is
  deferred; the initial extractor handles text-bearing PDFs.
- Check source listings once per day, subject to source conditions, and support
  manual collection. Immediate discovery guarantees are deferred.
- Store original PDFs in PostgreSQL with their metadata and acquisition records;
  enforce an initial 20 MiB (20,971,520 bytes) per-original limit and verify
  backup/restore. Record oversized downloads and acquisition errors as retryable
  failures without deleting existing originals to reclaim space. See
  [ADR 0002](adr/0002-store-pilot-originals-in-postgresql.md).
- Return one ordinary search result per earnings release using its latest
  successfully extracted original version. Keep historical originals accessible
  from detail. Explicitly flag older searchable text when a newer original's
  extraction fails.
- Identify a release by company, fiscal year-end, reporting period (Q1, Q2, Q3,
  or full year), and material category, independent of URL. Leave ambiguous
  identities pending confirmation rather than merging them automatically.
- Provide API and CLI access to search, originals, acquisition history, and
  extraction failures. A dedicated new screen is follow-up work.
- Keep existing company-attribute, analytical-review, and RSSHub issues outside
  v0.2. Preserve their scope and connect overlaps with related-issue links;
  v0.2 contains the new collection/preservation work required for this pilot.
- The planning work produced the ADRs, issue organization, documentation, and
  implementation handoff. Engineering work is tracked in the child issues; the
  implementation snapshot below records what has landed on the latest base.

## Current implementation boundary

The latest base contains deterministic source-listing discovery, PostgreSQL
original preservation with acquisition history, bounded PDF extraction, and
search over selected extracted text. The source routes remain inactive pending
their reviewed acquisition conditions. Bounded HTTP transport, immutable check
history, and run-budget helpers are present, but they are not yet connected to a
route-aware daily/manual earnings collector. The release detail/search API and
extraction CLI exist; original-byte/version retrieval, operator access to
unresolved and failed cases, identity confirmation, and backup/restore evidence
remain incomplete. See [#68](https://github.com/9renpoto/lens/issues/68) for the
current release checklist.

References: [ingestion](ingestion.md), [search](search.md),
[domain language](../CONTEXT.md), `lib/lens/ingestion.ex`,
`lib/lens/content/document.ex`, and `lib/lens/content/observation.ex`.

## Remaining delivery work and delegated choices

- [#69](https://github.com/9renpoto/lens/issues/69) verifies each company's actual acquisition route, access conditions, and
  listing-to-period mapping. Do not silently substitute companies or subscribe
  to a paid service if a route cannot be established; report the evidence and
  revisit that collection route before its adapter is enabled.
- The implementation has established the initial schemas, native PDF runner,
  release detail/search boundary, extraction CLI, and HTTP/run bounds. Remaining
  API/CLI operations and end-to-end recovery evidence are tracked in #73 and #74.
- Identity confirmation is an operator correction of ambiguous release metadata,
  not the analytical-review workflow in #48/#53.
- Saved-search baseline, publication versus first discovery, late arrivals, and
  result delivery remain explicitly deferred to [#75](https://github.com/9renpoto/lens/issues/75); they do not block v0.2.
- Planning decisions and issue relationships are recorded. Preservation and
  extraction foundations have landed; source access, complete collection/API
  behavior, and recovery verification remain tracked by #69, #71, #73, and #74.

## Delivery breakdown

1. Inventory candidate sources and establish a small evaluation corpus.
2. Specify original-material preservation and provenance requirements.
3. Specify acquisition, retry, and extraction/reprocessing boundaries.
4. Specify how derived searchable text relates to existing Documents.
5. Track saved-search monitoring as follow-up work dependent on this foundation.
6. Verify acquisition, extraction, search, and database restore end to end.

The [issue packet](next-minor-issues.md#reviewable-issue-packet) contains one
v0.2 tracker, six delivery issues, and one unmilestoned follow-up issue with
acceptance criteria and explicit dependencies.

## Release and issue inventory

GitHub has released [v0.1.0](https://github.com/9renpoto/lens/releases/tag/v0.1.0).
The [v0.1 milestone](https://github.com/9renpoto/lens/milestone/1) had eight
closed issues and no open issues at the 2026-09-15 inventory check; it was left
unchanged. After confirmation, [v0.2](https://github.com/9renpoto/lens/milestone/2)
was created with tracker #68 and six delivery issues #69–#74. Monitoring-design
issue #75 remains unmilestoned. This planning task does not bump application
versions or publish an application release.

See the [issue breakdown](next-minor-issues.md) for registered issue links,
dependencies, and existing-issue mapping. Six parent/child relationships and nine
blocking relationships were verified; existing issue bodies and metadata were
preserved. The tracker records the current implementation and outstanding
acceptance work.

## Documentation convention

Documents created in this planning session use English as the main text and a
matching Japanese translation inside a closed-by-default `<details>` block with
`<summary>日本語</summary>`. Keep both languages aligned when decisions change.

<details>
<summary>日本語</summary>

# 次のマイナーバージョンの計画

状態：合意した計画を[v0.2マイルストーン](https://github.com/9renpoto/lens/milestone/2)と[親issue #68](https://github.com/9renpoto/lens/issues/68)へ登録済み。最新ベースの`main`（`5bdd33b`、2026-10-04）には原本保存・本文抽出の基盤と、上限付きの発見・HTTP処理が含まれる。取得条件、日次・手動収集への接続、運用者向けAPI・CLI、DB復元の証跡は引き続きトラッカーで管理する。

## 合意した方針

- 収集候補を挙げて課題を分解しながら、収集・保存の基盤を優先する。
- 今回は少数社の決算情報を対象に、収集・原本保存・本文再生成・検索までを実現する。保存検索と新規公開の継続監視は、基盤に依存する後続issueに分ける。他の収集候補は今回の対象から外す。
- 最初の候補は日経平均への影響が大きい企業の決算情報。記録した基準日の構成比率上位3社を固定し、自動では入れ替えない。[取得元の評価](earnings-source-evaluation.md#fixed-pilot-company-set)を参照。
- 初期対象は日本語の決算短信PDF。収集開始時に各社の最新1回分を取得し、その後の新規掲載分を収集する。決算説明資料・数値の構造化・過去分の一括収集は後続に分ける。
- 企業公式IRを優先して調査し、パイロットの条件に合う取得経路を使う。有料のTDnet APIは代替候補として残すが、初期計画の前提とはしない。
- 初期の「監視」は、保存検索に一致する情報の新規公開を見つけることを指す。訂正の検出や前期との業績比較は、別の将来課題として扱う。
- 公式の原本資料・取得元URL・取得日時を保存し、保存済みの原本から検索用本文を再生成できるようにする。[ADR 0001](adr/0001-preserve-original-material-for-reprocessing.md)を参照。
- 同じURLの差し替えも含め、取得した異なる原本を上書きせず保持する。同じバイト列の再取得は、原本を重複保存せず取得履歴を追加する。訂正内容の意味的な比較は後続に分ける。
- 本文抽出に失敗しても取得した原本を保持する。取得と抽出の結果を分けて記録し、原本から抽出を再試行できるようにする。初期は文字情報を持つPDFに対応し、OCRは後続に分ける。
- 取得先の条件に従って1日1回一覧を確認し、手動収集も可能にする。即時性の保証は後続に分ける。
- 原本PDFをメタデータ・取得記録とともにPostgreSQLへ保存する。原本1件の初期上限を20 MiB（20,971,520バイト）とし、バックアップと復元を検証する。上限超過・取得エラーは再試行可能な失敗として記録し、容量確保のために既存原本を削除しない。[ADR 0002](adr/0002-store-pilot-originals-in-postgresql.md)を参照。
- 通常の検索では、決算短信ごとに本文抽出に成功した最新の原本の版を使って1件を返す。過去の原本は詳細から参照できるようにする。新しい原本の抽出が失敗した場合は、検索中の本文が旧版であることを明示する。
- 短信は、URLとは独立に、企業・決算期末・対象期間（第1〜第3四半期または通期）・資料種類で識別する。曖昧な場合は自動統合せず確認待ちにする。
- 検索・原本取得・取得履歴・抽出失敗の確認にはAPIとCLIを使う。新しい専用画面は後続に分ける。
- 既存の企業属性・分析レビュー・RSSHub関連issueはv0.2に含めない。既存の範囲を維持し、重複部分は関連リンクで結ぶ。v0.2には、このパイロットに必要な収集・保存の新規タスクを入れる。
- 計画作業でADR・issue整理・ドキュメント・実装担当への引き継ぎ資料を作成した。実装は子issueで管理し、以下に最新ベースへ反映済みの範囲を記録する。

## 最新ベースの実装状況

最新ベースには、取得元一覧からの決定的な発見、取得履歴を伴うPostgreSQL原本保存、上限付きPDF抽出、抽出本文を使う検索が含まれる。公式取得経路は、取得条件の確認が終わるまで無効。上限付きHTTP通信・変更不能な確認履歴・実行予算の基盤はあるが、検証済み経路を適用する日次・手動の決算収集処理には未接続。短信詳細・検索APIと抽出CLIはあるが、原本のバイト列・版の取得、未解決・失敗状態の運用者向け参照、識別確定、バックアップ・復元の証跡は未完了。現在のリリース状況は[#68](https://github.com/9renpoto/lens/issues/68)を参照。

参照：[収集](ingestion.md)、[検索](search.md)、[用語集](../CONTEXT.md)、`lib/lens/ingestion.ex`、`lib/lens/content/document.ex`、`lib/lens/content/observation.ex`。

## 残る実施作業と実装担当に委ねる選択

- [#69](https://github.com/9renpoto/lens/issues/69)で各社の実際の取得経路・取得条件・一覧から決算期への対応を検証する。経路を確立できない場合に対象企業を無断で入れ替えたり、有料サービスを契約したりせず、根拠を報告して、そのアダプターを有効にする前に経路を再検討する。
- 初期スキーマ、ネイティブPDF実行器、短信詳細・検索API、抽出CLI、HTTP・実行上限は実装済み。残るAPI・CLI操作と一連の復元検証は#73・#74で管理する。
- 識別情報の確認は、曖昧な短信メタデータを運用者が補正する作業であり、#48・#53の分析レビューとは異なる。
- 保存検索の初期基準、公開と初回発見の区別、遅れて発見した資料、結果の届け方は[#75](https://github.com/9renpoto/lens/issues/75)に明示的に先送りし、v0.2の前提にはしない。
- 計画上の決定とissueの関係を記録した。原本保存・本文抽出の基盤は実装済み。取得元の有効化、収集/APIの完成、復元検証は#69・#71・#73・#74で管理する。

## 実施タスクの分解

1. 取得元を一覧化し、小さな評価用資料群を確立する。
2. 原本保存と出典情報の要件を定義する。
3. 取得・再試行・本文抽出・再処理の境界を定義する。
4. 検索用本文と既存Documentの関係を定義する。
5. 保存検索による監視を、今回の基盤に依存する後続課題として管理する。
6. 取得・本文抽出・検索・DB復元を一連の流れで検証する。

[issue一式](next-minor-issues.md#reviewable-issue-packet)には、v0.2の親issue、6件の実施issue、マイルストーン未設定の後続issueをまとめ、受入条件と依存関係を記載している。

## リリースとissueの現状

GitHubでは[v0.1.0](https://github.com/9renpoto/lens/releases/tag/v0.1.0)が公開済み。2026-09-15の棚卸し時点で[v0.1マイルストーン](https://github.com/9renpoto/lens/milestone/1)は8件完了・未完了0件であり、変更していない。合意確認後に[v0.2](https://github.com/9renpoto/lens/milestone/2)を作成し、親issue #68と6件の実施issue #69〜#74を登録した。監視設計の#75はマイルストーン未設定で残す。この計画作業ではアプリのバージョン変更やリリース公開は行わない。

登録済みissueのリンク・依存関係・既存issueとの対応は[issue分解](next-minor-issues.md)を参照。親子関係6件・依存関係9件を確認し、既存issueの本文・メタデータは維持した。現在の実装状況と残作業は親issue #68に反映する。

## ドキュメントの表記規則

この計画作業で作成するドキュメントは英語を本文とし、対応する日本語訳を、初期状態で閉じた`<details>`内に置く。見出しは`<summary>日本語</summary>`とする。決定を変更した際は両言語を同時に更新する。

</details>
