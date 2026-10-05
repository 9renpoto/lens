---
status: accepted
---

# Store PDFs in RustFS

Use RustFS to store and retrieve earnings PDFs. Keep acquisition records, document identity and extracted text in PostgreSQL. The aim is to simplify Lens by delegating file storage to a dedicated service. Judge that simplification across the whole operation, including backup and recovery, rather than by Lens code size alone.

Keep identical PDF contents only once and retain changed contents as separate files. Give each file a stable location based on its contents; do not overwrite one location and rely on storage version history to identify the PDF used. Lens still determines which company and reporting period a document belongs to and which extracted text is used for search.

Keeping PDFs in PostgreSQL would allow files and their records to be backed up together without another service. We instead accept operating RustFS and coordinating file and record recovery in order to delegate file storage. Back up and restore PostgreSQL and RustFS as one recovery point. After restoration, reconcile every completed database reference against the RustFS object key and content hash. Repair a missing or mismatched object from the coordinated backup when possible; if no valid copy exists, mark the original unavailable and surface it for operator recovery. Never treat the release as complete or silently serve a different PDF. This protects against inconsistent restores that ordinary interrupted-write recovery cannot detect. Follow [ADR 0006](0006-record-file-storage-work-before-writing.md) for interrupted writes.

Consider migration to another compatible storage service only when a need arises. Do not build support for multiple storage products in this release. This is a storage decision, not a claim that the existing PostgreSQL implementation has already been migrated.

<details>
<summary>日本語</summary>

# PDFをRustFSに保存する

決算短信PDFの保存・取得にはRustFSを使う。取得記録、資料の識別情報、読み取った文章はPostgreSQLに残す。ファイルの保存を専用サービスに任せ、Lensの処理を簡単にすることが目的。Lensのコード量だけでなく、バックアップ・復旧を含む運用全体の簡単さで評価する。

同じ内容のPDFは一つだけ保存し、変更された内容は別のファイルとして残す。各ファイルには内容に基づく固定の保存場所を与える。一つの場所へ上書きしてストレージの版履歴に頼り、使用したPDFを識別する方法は取らない。どの企業・決算の資料か、検索にどの抽出本文を使うかはLensが判断する。

PDFをPostgreSQLに残せば、別のサービスを運用せずファイルと記録をまとめてバックアップできる。今回はファイル保存を任せるため、RustFSの運用と、ファイル・記録を揃えて復旧する責任を引き受ける。PostgreSQLとRustFSは一つの復旧時点としてバックアップ・復元する。復元後は、DB上の完了済み記録を一件ずつRustFSのオブジェクトキーと内容ハッシュに照合する。欠落・不一致のファイルは、可能なら同じ復旧用バックアップから修復する。有効なコピーがなければ原本を利用不可として運用者に示し、処理完了として扱ったり、別のPDFを黙って返したりしない。これは通常の中断書き込み復旧では検出できない、整合しない復元から守るためである。中断書き込みには[ADR 0006](0006-record-file-storage-work-before-writing.md)を適用し、保存前に作業記録を残し、回数を制限した自動復旧と手動復旧に対応する。

他の互換ストレージへの移行は、必要になった時点で検討する。今回のリリースでは複数製品への対応を作り込まない。これは保存先の決定であり、既存のPostgreSQL実装の移行完了を意味しない。

</details>
