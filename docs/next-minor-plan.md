# v0.2 direction

Build a small earnings-PDF pilot that can collect materials, retain originals, read their text again, search them and recover saved data. Limit targets through operator configuration, not a prescribed company list in code or documentation.

## Agreed methods and reasons

- [Retain PDFs separately from their text](adr/0004-retain-earnings-pdfs-for-reprocessing.md), so reading mistakes can be corrected even if the publisher removes the PDF.
- [Store PDFs in RustFS](adr/0005-store-pdfs-in-rustfs.md), delegating file custody while PostgreSQL holds acquisition records, identity and extracted text. Consider compatible storage migration only when needed.
- [Record storage work before writing files](adr/0006-record-file-storage-work-before-writing.md), so interrupted work can be recovered after restart. Bound automatic retries and allow manual recovery.
- [Register targets and sources through an API](adr/0007-register-pilot-sources-through-an-interface.md), so changing the pilot does not require changing application code. Add a web UI when needed.
- Verify the deployed pilot using Lens running on the operator's local k3s cluster. Keep deterministic automated tests for production changes.

## Decisions still to discuss

Pause the interview here. Do not interpret the previous implementation or historical issue packet as agreement on these remaining choices:

- Collection routes, acquisition conditions, daily/manual operation and retry policy.
- Release identification, ambiguous identity and correction materials.
- Text processing, regeneration and image-only PDFs.
- Search-version selection, stale-text indication and large-text search behavior.
- Operator access to originals, history, failures and identity confirmation.
- Coordinated RustFS/database backup and recovery, and the deployment verification scenarios.

Saved-search monitoring, financial analysis and bulk historical collection remain follow-up work. See [the revised task breakdown](next-minor-issues.md). This planning revision does not implement or deploy the changes.

<details>
<summary>日本語</summary>

# v0.2の方針

決算短信PDFを対象に、収集・原本保存・本文の読み取り直し・検索・保存データの復旧ができる小規模なパイロットを作る。対象は運用者の設定で限定し、コードや文書に特定の企業一覧を運用方針として固定しない。

## 合意した手段と理由

- [PDFを本文と別に残す](adr/0004-retain-earnings-pdfs-for-reprocessing.md)。公開元からPDFが消えても読み取りの誤りを修正できるようにする。
- [PDFはRustFSに保存する](adr/0005-store-pdfs-in-rustfs.md)。ファイルの保管を任せ、取得記録・識別情報・抽出本文はPostgreSQLに残す。互換ストレージへの移行は必要時に検討する。
- [ファイル保存前に作業を記録する](adr/0006-record-file-storage-work-before-writing.md)。再起動後も中断した作業を復旧できるようにする。自動再試行は回数を制限し、手動復旧も可能にする。
- [対象と取得先はAPIで登録する](adr/0007-register-pilot-sources-through-an-interface.md)。対象変更のためにアプリのコードを変更せずに済むようにする。Web UIは必要時に追加する。
- 実環境でのパイロット検証には、運用者のローカルk3s上のLensを使う。本番変更には引き続き再現可能な自動テストを使う。

## 今後議論する判断

ここで議論を中断する。以下について、既存実装や過去のIssue文書を今回の合意とは扱わない。

- 取得経路・取得条件・日次／手動実行・再試行方針。
- 短信の識別・曖昧な識別情報・訂正資料。
- 本文処理・再生成・画像だけのPDF。
- 検索対象版・旧版本文の表示・大きな本文の検索方法。
- 原本・履歴・失敗の参照と、運用者による識別確定。
- RustFSとデータベースを揃えるバックアップ・復旧、実環境での検証シナリオ。

保存検索による監視、財務分析、過去資料の一括収集は後続に残す。[見直したタスク分解](next-minor-issues.md)を参照。この計画更新では実装・デプロイは行わない。

</details>
