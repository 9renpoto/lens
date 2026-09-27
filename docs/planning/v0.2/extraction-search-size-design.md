# Extraction search size design review

Status: option 1 selected after returning to design following
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

## Selected contract: option 1

Implementation resumed after documenting the contract and verifying that adding
the generated column and both indexes to pre-existing 8 MiB text preserves every
byte and tail matching. This is an engineering decision; no user approval is
claimed. A production regression first reproduced SQLSTATE 54000 on completion;
the bounded-vector migration and null-rank handling now pass the five earnings
search tests. API availability flags and the remaining regression gates below
are still required before the draft PR becomes ready.

- Retain all accepted plain text, up to the existing 8 MiB extraction ceiling,
  and its complete NFKC/lowercase search representation. Do not build a vector
  from a truncated prefix or silently lower the extraction limit.
- Use a strict immutable database function to derive a complete vector. Catch
  only PostgreSQL `program_limit_exceeded`; return null in that case. Null input
  remains null. Other database errors propagate rather than becoming invisible
  search limitations. The generated column invokes this function for existing
  rows, new completions and later regeneration alike.
- Expose `search_mode` for the selected extraction: `full_text` when a vector
  exists, `substring` when successful text has no vector, and `none` for attempts
  without successful text. This is derived-search availability, not an
  acquisition or extraction failure. A vector limit must not make valid text
  lose `succeeded` status or make the older original preferred.
- Continue literal normalized substring matching across the entire text. Give
  null-vector rows a full-text rank of zero, retaining deterministic ID ties.
  Full-text boolean/phrase operations apply only where the vector is available;
  no claim is made that a fallback interprets AND/OR/NOT as operators.
- The search response needs a query-scope `full_text_complete` flag, false when
  any selected eligible earnings text lacks a vector. Derive this from all
  selected text, before matching and pagination, in the same database snapshot.
  Per-result flags alone cannot explain zero results from an unsupported boolean
  match or omissions beyond the current page. Feed behavior remains unchanged.
- Rebuild the full normalized substring representation using the shared
  normalizer, without acquisition/extraction. Schema migration must allow
  already successful large text. Existing extracted text and selection rules
  remain authoritative; no asynchronous selected pointer is introduced.

Additional session-local verification used exactly 8,388,608 bytes of ASCII
distinct-token/repeated text with an end marker. Both GIN indexes were created;
the vector was null, the end marker matched and its proposed rank was zero.
Pending/failed null-body rows yielded `none`; an ordinary successful body yielded
`full_text`. Updating successful bodies to themselves recomputed derived vectors
without error and preserved tail matching. These are design-prototype results,
not verification of a production implementation.

Required regression gates before marking the PR ready: migration over pre-existing
large successful text, successful new completion at the accepted ceiling, exact
text/paragraph preservation, end-marker matching, status/detail flags, query-scope
flag on zero results and later pages, unchanged selection/stale rules, rebuilding,
shared normalization, and feed/CJK regressions. The semantic choice is option 1.

<details>
<summary>日本語</summary>

# 抽出本文の検索サイズ設計レビュー

状態：[PR #90 の指摘](https://github.com/9renpoto/lens/pull/90#discussion_r4113270427)を受けて
設計へ戻り、第1案を選択した。既存実装とCI成功だけでは #72 の完成を証明できない。

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

## 選択した契約：第1案

契約を記録し、既存の8 MiB本文へ生成列と両索引を追加しても全バイトと末尾照合を保持する
ことを確認して、実装を再開した。これは技術上の判断であり、ユーザー承認を得たとはしない。
本番回帰テストで完了時のSQLSTATE 54000を先に再現し、安全なベクトル生成とnull順位の
対応後は決算検索の5テストが成功した。APIの利用可否フラグと以下の残りの回帰条件は、
ドラフトPRをreadyに戻す前に引き続き必要。

- 既存の抽出上限8 MiBまでの本文と、全文のNFKC・小文字化検索表現を保持する。
  先頭だけのベクトルや、説明なしの抽出上限引下げは使わない。
- STRICT・IMMUTABLEなDB関数で全ベクトルを生成し、`program_limit_exceeded` だけを
  捕捉してnullにする。null入力はnullのまま。他のDBエラーは隠さない。
  生成列は既存行、新規完了、再生成のいずれも同じ関数を使う。
- 選択抽出の `search_mode` は、ベクトルありで `full_text`、成功本文のみで `substring`、
  成功本文なしで `none` とする。これは検索派生表現の利用可否であり、取得・抽出失敗ではない。
  ベクトル上限で有効本文の `succeeded` を取り消したり、旧原本を優先したりしない。
- 正規化済みの文字列部分一致は全文を対象にする。nullベクトルの全文順位は0とし、
  IDによる決定的な同順位を維持する。全文検索の論理・句操作はベクトルがある場合だけであり、
  フォールバックでAND・OR・NOTを演算子として扱うとはしない。
- 検索応答全体に `full_text_complete` を設け、選択済み対象本文にベクトルなしが1件でも
  あればfalseとする。照合・ページング前の全選択本文から同じDBスナップショットで導出する。
  結果ごとのフラグだけでは、未対応の論理照合で0件になる場合や別ページの欠落を説明できない。
  フィードの動作は維持する。
- 取得・抽出なしで、共通正規化により全文の部分一致表現を再構築する。
  既存の大きな成功本文もマイグレーション可能にする。保存本文・選択規則を正とし、
  非同期の選択ポインタは追加しない。

追加の一時DB検証では、異なる語と反復を組み合わせ、末尾マーカー付きで8,388,608バイト
ちょうどの本文を使った。両GIN索引を作成でき、ベクトルはnull、末尾照合は成功、提案順位は0。
待機・失敗のnull本文は `none`、通常の成功本文は `full_text`。成功本文を同じ本文で更新しても
再計算エラーはなく、末尾照合を維持した。本番実装の検証ではなく設計試作の結果である。

PRをreadyに戻す前の回帰条件は、既存大型成功本文のマイグレーション、上限サイズの新規成功、
本文・段落の一致、末尾照合、状態・詳細フラグ、0件や別ページでの応答全体のフラグ、
選択・旧版規則、再構築、共通正規化、フィード・CJK回帰。検索の意味は第1案を選択した。

</details>
