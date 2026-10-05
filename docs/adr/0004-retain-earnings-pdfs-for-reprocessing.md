---
status: accepted
---

# Keep earnings PDFs so their text can be read again

Keep each successfully acquired, accepted earnings PDF unchanged, separately from the text read from it. The current acquisition limit is 20 MiB per original; larger candidates are rejected and are not retained as originals. See [the accepted size limit](0002-store-pilot-originals-in-postgresql.md). Read the text again from a saved PDF when the reading method needs correction or improvement.

Keeping only the extracted text would lose the material needed to correct reading mistakes. Keeping only the publisher's link would depend on the PDF remaining available there. Saving the PDF takes additional storage, but makes later text processing independent of the publisher's website.

<details>
<summary>日本語</summary>

# 本文を読み取り直せるように決算短信PDFを残す

取得に成功し受け入れた決算短信PDFは変更せず、そこから読み取った文章とは別に保存する。現在の原本サイズ上限は20 MiBであり、上限を超える候補は拒否し、原本として保存しない。[合意済みのサイズ上限](0002-store-pilot-originals-in-postgresql.md)を参照する。読み取り方法の修正や改善が必要になった場合は、保存済みPDFから文章を読み取り直す。

読み取った文章だけを残すと、読み取りの誤りを修正するための資料が失われる。公開元のリンクだけを残すと、公開元でPDFを引き続き取得できることに依存する。PDFの保存には追加の容量が必要だが、後から行う本文の処理を公開元のウェブサイトに依存せず実施できる。

</details>
