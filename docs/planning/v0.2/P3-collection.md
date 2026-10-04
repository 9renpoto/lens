# Collect earnings PDFs with bounded daily and manual runs

GitHub issue: [#71](https://github.com/9renpoto/lens/issues/71)

## Objective

Discover and acquire the fixed pilot's Japanese earnings PDFs through the reviewed official routes.

## Details

Initialize each company with its latest regular reporting release using #69's rule, then collect newly listed releases. Support daily scheduling and a manual CLI run. The source catalog is a fixed pilot configuration, not the historical target/membership model in #43.

## Checklist

- [ ] Apply #69's per-company link discovery and identity mapping, preserving unknown publication dates and pending identities.
- [ ] Initial collection excludes bulk history; later runs acquire new regular releases without repeatedly importing older listings.
- [ ] Recheck retained pilot document URLs within the bounded collection scope so changed bytes at an existing URL can be preserved. Document the checked set and request bound; separately listed correction analysis is outside scope.
- [ ] Daily and manual runs use the same acquisition path and do not overlap for the same source. Distinguish actual repeated downloads from retries of the same persistence operation.
- [ ] Enforce the 20 MiB limit on actual response bytes, including missing/misleading Content-Length. Bound redirects, request duration, and requests per run; record failures without losing prior originals.
- [ ] Keep HTTP failures, non-PDF responses, interrupted downloads, unchanged responses, and successful acquisitions distinguishable. A 304 records a check without inventing newly downloaded bytes.
- [ ] Provide retryable outcomes with capped retry/backoff behavior, respecting source conditions, and regression coverage for existing feed ingestion.

## Dependencies

Blocked by [#69](P1-source-catalog.md) and [#70](P2-preservation.md).

## Notes

Use local HTTP/listing fixtures for TDD and record live-source verification separately. Implementer chooses timeout/backoff values and CLI names with documented bounds. Acquisition is direct from the reviewed routes; RSSHub #44/#54 is not a prerequisite.

<details>
<summary>日本語</summary>

# 日次・手動実行で上限付きの決算PDF収集を行う

GitHub issue: [#71](https://github.com/9renpoto/lens/issues/71)

## 目的

固定パイロットの日本語決算PDFを、検証済みの公式経路から発見・取得する。

## 詳細

#69の規則で各社の最新の通常決算短信を初回取得し、その後の新規掲載分を収集する。日次スケジュールと手動CLI実行を提供する。取得元台帳は固定のパイロット設定であり、#43の対象・構成銘柄履歴モデルとは区別する。

## チェックリスト

- [ ] #69の企業別リンク発見・識別規則を適用し、不明な公開日と確認待ちの識別情報を保持する。
- [ ] 初回に過去分を一括取得せず、以後は古い一覧を繰り返し取り込まず新しい通常短信を取得する。
- [ ] 保存済みのパイロット資料URLを収集範囲と件数の上限内で再確認し、同一URLのバイト列変更を保存できるようにする。確認対象とリクエスト上限を記録する。別掲載の訂正資料の分析は対象外。
- [ ] 日次・手動実行で取得処理を共通化し、同じ収集元で重複実行しない。実際の再ダウンロードと、同じ取得の保存処理の再試行を区別する。
- [ ] Content-Lengthが欠落・不正確な場合も、実際の応答バイト列に20 MiB上限を適用する。リダイレクト・所要時間・実行あたりリクエスト数に上限を設け、失敗時も過去原本を維持する。
- [ ] HTTP失敗・PDF以外の応答・中断した取得・未変更応答・取得成功を区別する。304は確認として記録し、新たなダウンロードを捏造しない。
- [ ] 取得先の条件に従い、上限付きの再試行・待機時間で再試行可能な結果を返す。既存フィード収集の回帰検証を行う。

## 依存関係

[#69](P1-source-catalog.md)・[#70](P2-preservation.md)の完了が必要。

## 補足

TDDにはローカルのHTTP・一覧の固定データを使い、実サイトの検証を別途記録する。タイムアウト・再試行値・CLI名は実装担当が上限とともに記録する。検証済み経路から直接取得し、RSSHubの#44・#54は前提としない。

</details>
