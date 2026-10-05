---
status: accepted
---

# Record file storage work before saving the PDF

If Lens uses a separate file storage service, save a work record in the database before writing the PDF. Record its acquisition source, intended storage location and the information needed to identify the acquired PDF. Do not start the storage write if the work record cannot be saved.

Memory-only work tracking disappears when the application restarts. A database work record lets recovery find unfinished work after restart, check whether the PDF was saved and complete its corresponding acquisition record. Treat storage as complete only when both the PDF and its record are available. When the PDF is already saved, reuse it instead of downloading it again from the publisher.

Allow automatic recovery with a finite retry count and manual recovery by the operator. Repeating recovery must not duplicate records or overwrite saved PDFs. When automatic retries reach their limit, retain the unfinished work for operator attention. The exact retry count and spacing remain undecided.

This adds persistent work tracking, but makes interrupted storage recoverable without relying on process memory. It is a condition for adopting external storage, not a selection of a storage product or a statement that recovery is already implemented. See [the storage comparison](0005-store-pilot-pdfs-with-their-records.md).

<details>
<summary>日本語</summary>

# PDFを保存する前に保存作業を記録する

Lensで独立したファイル保存サービスを使う場合、PDFを書き込む前にデータベースへ作業記録を残す。取得元・予定する保存先・取得したPDFを識別するための情報を記録する。作業記録を保存できない場合は、ストレージへの書き込みを始めない。

メモリだけで作業を管理すると、アプリの再起動でその情報が消える。データベースに作業記録を残すことで、再起動後に未完了の作業を見つけ、PDFが保存済みか確認し、対応する取得記録を完成させられる。PDFと対応する記録が両方揃ってから保存完了と扱う。PDFが保存済みの場合は、公開元から取り直さず再利用する。

自動復旧は再試行回数を制限し、運用者による手動復旧も可能にする。繰り返しても記録の重複や保存済みPDFの上書きを起こさない。自動再試行が上限に達した場合は、未完了の作業を残して運用者の対応を待つ。具体的な再試行回数と間隔は未決定。

永続的な作業管理は増えるが、メモリに頼らず中断した保存処理を復旧できるようになる。これは外部ストレージの採用条件であり、製品の選定や復旧機能の実装完了を意味しない。[保存先の比較](0005-store-pilot-pdfs-with-their-records.md)を参照。

</details>
