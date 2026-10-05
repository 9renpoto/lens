---
status: accepted
---

# Register collection targets through an operator interface

Limit the initial earnings pilot to a small set of targets chosen by the operator. Provide an API for registering and changing companies and their acquisition sources, rather than embedding particular company names, codes or source routes as the supported set in application code or documentation. Start with the API and add a web UI when needed; the UI can use the same API. This keeps the initial interface small.

This keeps the pilot small without requiring code changes whenever its targets change. Documentation explains how to choose and register targets; it does not prescribe a fixed company set. Source conditions still need review before acquisition is enabled.

Use the Lens instance running on the operator's local k3s cluster for deployment-level pilot verification. This checks the environment that will actually be operated. Focused automated tests remain necessary for production changes; this decision does not replace them or claim that pilot verification is complete.

<details>
<summary>日本語</summary>

# 運用者向けインターフェースから収集対象を登録する

初期の決算情報パイロットは、運用者が選ぶ少数の対象に限定する。特定の企業名・コード・取得経路を対応対象としてアプリのコードや文書に固定せず、企業と取得先を登録・変更できるAPIを設ける。まずAPIから始め、Web UIは必要になった時点で追加し、同じAPIを利用する。これにより初期のインターフェースを小さくする。

これにより、対象を変えるたびにコードを変更せず、小規模なパイロットを運用できる。文書では対象の選び方と登録方法を説明し、固定の企業一覧を運用方針として指定しない。取得を有効にする前に、取得先の条件を確認する必要は引き続きある。

実環境でのパイロット検証には、運用者のローカルk3s上で稼働するLensを使う。実際に運用する環境で確認するため。本番変更には引き続き対象を絞った自動テストが必要であり、この決定はその代替やパイロット検証の完了を意味しない。

</details>
