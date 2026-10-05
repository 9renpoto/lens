---
status: proposed
---

# Store pilot PDFs and their records in the same database

The storage choice is being reconsidered against a separate file storage service such as RustFS. The database option below remains a proposal until that comparison is settled.

The accepted recovery policy is recorded in [ADR 0006](0006-record-file-storage-work-before-writing.md).

The comparison focuses on simplifying Lens, rather than increasing storage capacity. Evaluate delegating PDF storage, retrieval and retention of earlier file versions to the storage service. Lens still determines which company and reporting period a document belongs to, and which extracted text is used for search. The storage service and the way it retains versions have not yet been selected.

Judge the alternatives by the simplicity of the whole operation, including backup and recovery, rather than by the amount of Lens code alone. Moving work into a storage service is worthwhile only if the work needed to keep files and their records consistent does not outweigh the simplification.

Introducing an additional storage service is acceptable if it reduces that overall operational work. The comparison is not limited to services already in use.

External storage must support recovery that can be started later when PDF storage succeeds but its database record does not. Treat storage as complete only when the PDF and its corresponding record are both available. Recovery reuses the saved PDF rather than downloading it again from the publisher. This is an adoption condition, not a claim that recovery already exists.

Before writing the PDF to external storage, persist a work record containing its acquisition source, intended storage location and the information needed to identify the acquired PDF. If that record cannot be saved, do not start the storage write. Keep unfinished work discoverable after an application restart so recovery can check the saved file and complete its acquisition record. A work record describes intended work; it must not claim that a file has already been saved.

Allow automatic recovery with a finite retry count, and allow the operator to restart recovery manually. Automatic recovery must be safe to repeat without duplicating records or overwriting saved PDFs. After the retry limit, retain the unfinished work for operator attention rather than retrying indefinitely. The exact retry count and spacing remain undecided.

For the external-storage option, keep identical PDF contents only once and retain changed contents as separate files. Give each file a stable location based on its contents, rather than overwriting one location and relying on the service's version history. Lens records which saved file was acquired and read. This preserves a clear link to the exact PDF without adding a separate storage-version identifier. Whether to adopt external storage remains open.

Store the fixed three-company pilot's PDFs in PostgreSQL, the database that also holds their acquisition records and extracted text. This lets the operator back up and restore the saved materials and their records together.

Storing PDFs in a separate folder or file storage service would require coordinating that storage with the database during backup and recovery. For this small pilot, keeping them together simplifies operation. PDF storage increases the size of the database and its backups; reconsider separate storage if that burden becomes too large.

<details>
<summary>日本語</summary>

# パイロットのPDFと関連記録を同じデータベースに保存する

保存先は、RustFSなどの独立したファイル保存サービスと比較して再検討している。以下のデータベース案は、比較の結論が出るまで提案として扱う。

合意した復旧方針は[ADR 0006](0006-record-file-storage-work-before-writing.md)に記録する。

比較の目的は容量の拡大ではなく、Lensの処理を簡単にすること。PDFの保存・取得・過去のファイル版の保持を保存サービスに任せる案を検討する。どの企業・決算の資料か、検索にどの抽出本文を使うかはLensが判断する。保存サービスと、過去版を保持する具体的な方法はまだ選定していない。

Lensのコード量だけでなく、バックアップ・復元を含む運用全体の簡単さで比較する。ファイルと関連記録の整合を保つための作業が、処理を任せる利点を上回らない場合に保存サービスを採用する価値がある。

運用全体の作業が減るなら、保存サービスを新たに一つ導入することも許容する。比較対象は既に使っているサービスだけに限定しない。

外部ストレージの採用条件として、PDFの保存に成功してもデータベースへの記録に失敗した場合に、後から復旧処理を起動できるようにする。PDFと対応する記録が両方揃ってから保存完了と扱う。復旧では保存済みPDFを使い、公開元から取り直さない。この条件は、復旧機能が既にあることを意味しない。

外部ストレージへPDFを書き込む前に、取得元・予定する保存先・取得したPDFを識別するための情報を作業記録として永続的に残す。この記録を保存できない場合は、ストレージへの書き込みを始めない。未完了の作業はアプリの再起動後も見つけられるようにし、復旧処理で保存済みファイルを確認して取得記録を完成させる。作業記録はこれから行う処理を表すものであり、ファイルの保存が既に成功したとは扱わない。

自動復旧は再試行回数を制限し、運用者が手動で復旧を再実行することも可能にする。自動復旧は、繰り返しても記録の重複や保存済みPDFの上書きを起こさないことを条件にする。上限に達した場合は無期限に繰り返さず、未完了の作業を残して運用者の対応を待つ。具体的な再試行回数と間隔は未決定。

外部ストレージ案では、同じ内容のPDFは一つだけ保存し、変更された内容は別のファイルとして残す。一つの保存場所へ上書きしてサービスの版履歴に頼るのではなく、内容に基づく固定の保存場所を各ファイルに与える。Lensは、どの保存済みファイルを取得し、読み取ったかを記録する。これにより、ストレージ独自の版番号を新たに管理せず、実際に使ったPDFとの対応を明確に保つ。外部ストレージを採用するかは未決定。

固定3社のパイロットでは、PDFを、取得記録や読み取った文章も管理するデータベースであるPostgreSQLに保存する。運用者は、保存した資料と関連記録をまとめてバックアップ・復元できる。

PDFを別のフォルダーやファイル保存サービスに置く場合、バックアップ・復元の際に、その保存先とデータベースを整合させる必要がある。小規模なパイロットでは、一緒に保存することで運用を簡単にする。PDFの保存によってデータベースとバックアップの容量は増えるため、その負担が大きくなった場合は別の保存先を再検討する。

</details>
