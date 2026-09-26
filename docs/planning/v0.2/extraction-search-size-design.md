# Extraction search size design review

Status: design phase; production implementation stopped following
[PR #90 review](https://github.com/9renpoto/lens/pull/90#discussion_r4113270427).
The existing implementation and green CI do not establish completion of #72.

## Verified problem

Extraction permits up to 8 MiB of UTF-8 text, but a PostgreSQL `tsvector` must
remain below 1 MiB. This is a **generated-vector** limit, not a fixed input-size
limit. On the scratch PostgreSQL 17 database, 3,000,000 bytes of repeated Japanese
text generated a 534-byte vector, while 100,000 distinct English tokens produced
the error `string is too long for tsvector (1379804 bytes, max 1048575 bytes)`.
The latter input with a tail marker was only 988,917 bytes. Reducing the extraction
limit to 1 MiB therefore does not guarantee successful indexing.

The generated column currently makes this search-derived failure abort saving
otherwise valid extracted text, and may prevent migration of existing successful
extractions. Acquisition and extraction correctness must not depend on the
availability of this particular search representation.

Reference: [PostgreSQL text search limits](https://www.postgresql.org/docs/17/textsearch-limitations.html).

## Options under consideration

1. Keep a complete normalised trigram field and attempt the full vector. If
   vector generation exceeds its program limit, retain a null vector and expose
   that full-text operations are unavailable. Match the complete normalized
   substring instead. This preserves text and ordinary CJK matching, but does
   not preserve English AND/OR semantics on vector-unavailable rows.
2. Use normalized substring search for all earnings text, keeping feed behavior
   intact. This gives a consistent earnings contract without vector-size failure,
   but deliberately removes earnings full-text operators and ranking.
3. Design segmented indexes and cross-segment query evaluation. Simply matching
   one chunk does not preserve AND across chunks or correct NOT semantics. This
   needs an explicit query-language and ranking design before implementation.

No option truncates retained text or original bytes. Prefix-only vectors are not
an adequate complete-text search representation. Changing the extraction limit
alone is not an adequate fix either.

A session-local SQL prototype of option 1 caught `program_limit_exceeded`, kept
the complete body and generated a null vector for the 988,917-byte distinct-token
case. A trigram index was built successfully, and the Japanese tail marker
matched. The multiword vector query did not match, confirming the semantic tradeoff.
This prototype used only temporary database objects; no production code changed.

The user was asked which search contract to prioritize. Before resuming code,
record the chosen contract, its visible indexing status and migration behavior.
Then write regression tests for pre-existing large successful extractions,
new completion, tail search, rebuilding and any affected operator semantics.

<details>
<summary>日本語</summary>

# 抽出本文の検索サイズ設計レビュー

状態：設計フェーズ。[PR #90 の指摘](https://github.com/9renpoto/lens/pull/90#discussion_r4113270427)を受け、
本番実装を中断した。既存実装とCI成功だけでは #72 の完成を証明できない。

## 実証した問題

抽出はUTF-8本文8 MiBまで許可するが、PostgreSQLの `tsvector` は1 MiB未満の制約がある。
これは固定の入力サイズではなく、生成ベクトルのサイズ制約。使い捨てPostgreSQL 17で、
日本語反復本文3,000,000バイトは534バイトのベクトルになり、異なる英語語彙100,000件は
1,379,804バイトのベクトルとして上限1,048,575バイトを超えた。末尾マーカー付きでも入力は
988,917バイトだった。抽出上限を1 MiBへ下げても索引化成功は保証できない。

現在の生成列では、検索派生データの失敗が有効な抽出本文の保存を中断し、既存成功本文の
マイグレーションも妨げ得る。取得・抽出の正しさを、特定の検索表現の利用可否に依存させない。
[PostgreSQLの公式制約](https://www.postgresql.org/docs/17/textsearch-limitations.html)を参照。

## 検討する選択肢

1. 全文の正規化済みtrigramフィールドを保持し、全文ベクトルも生成する。ベクトル上限超過時は
   nullにして全文検索操作が利用不可であることを明示し、全文の部分一致を使う。
   本文と通常のCJK照合を維持できるが、該当行の英語AND・OR検索の意味は維持できない。
2. 決算本文はすべて正規化済み部分一致に統一する。フィードは維持する。
   決算の契約は一貫するが、全文検索演算子と全文順位付けを取り除く。
3. 分割索引と区間をまたぐ検索評価を設計する。1区間だけの照合では区間をまたぐANDやNOTの
   正しさを維持できず、検索言語と順位の設計が必要。

いずれも保存本文・原本は切り捨てない。先頭だけのベクトルは全文検索として不十分。
抽出上限だけの変更も十分な解決ではない。

第1案のセッション内SQL試作は `program_limit_exceeded` を捕捉し、988,917バイトの本文を
保持してベクトルをnullにした。trigram索引の作成と末尾日本語マーカーの照合は成功し、
複数語のベクトル検索は不一致となり、意味の違いも確認した。一時DBオブジェクトだけを使い、
本番コードは変更していない。

優先する検索契約をユーザーへ質問した。実装再開前に、選んだ契約・見える索引状態・
マイグレーション挙動を記録し、既存の大きな成功本文、新規完了、末尾検索、再構築、
影響する検索演算子の回帰テストを書く。

</details>
