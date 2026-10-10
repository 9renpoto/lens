# Lens

Lens is a personal web observatory for collecting, preserving, searching, and
discovering information over time.

## Language

**Analysis target**:
A security selected by the operator for analysis. Being an analysis target does not itself mean that earnings acquisition is enabled.
_Avoid_: Analytics target

**Earnings acquisition source**:
A route associated with an analysis target from which earnings documents can be discovered and acquired.

**Document candidate**:
An acquired document considered for inclusion among a target's earnings materials. Acquisition alone does not establish its document kind or reporting identity.

**Document assessment**:
A judgment about a candidate's relationship to an analysis target and earnings document kind, with supporting evidence. An inconclusive assessment leaves the candidate pending confirmation.

**Operator decision**:
An explicit human decision to adopt or exclude a document candidate. It is distinct from an automated document assessment.

**Earnings release**:
A company's published summary of its financial results for a reporting period.
In the pilot, its identity is the company, fiscal year-end, reporting period
(Q1, Q2, Q3, or full year), and material category, independent of its URL.
_Avoid_: Earnings presentation, annual securities report

**Pilot company set**:
The small set of companies chosen by the operator for earnings collection.
_Avoid_: Hardcoded issuer list, index ranking

**Original material**:
The source material as acquired from its publisher, before text extraction or
normalization.
_Avoid_: Extracted text, search index

**Acquisition time**:
The time Lens obtained source material. It is distinct from the publication
time reported by the publisher.
_Avoid_: Publication time

**Original version**:
A distinct byte representation of acquired original material. Reacquiring the
same bytes does not create another original version.
_Avoid_: URL, extraction result

**Physical storage location**:
A verified copy of an original version in one storage backend, identified by its
backend and immutable location key.

**Active read location**:
The physical storage location currently selected for reads of one original
version. Its selection is stored separately from the original's identity.

**Acquisition record**:
A record of obtaining original material from a location at a particular time.
Multiple acquisition records may refer to the same original version.
_Avoid_: Original version, publication event

**Extracted text**:
Text derived from an original version for reading and searching, which can be
regenerated from that original.
_Avoid_: Original material

**Saved search**:
A retained set of search conditions used to find matching information over time.
_Avoid_: Source subscription

**New-publication monitoring**:
Finding newly published information that matches a saved search.
_Avoid_: Revision detection, period-over-period financial comparison

<details>
<summary>日本語</summary>

# Lens

Lensは、情報を継続して収集・保存・検索・発見するための個人向けWeb観測基盤です。

## 用語

**Analysis target（分析対象）**:
運用者が分析のために選んだ銘柄。分析対象であること自体は、決算資料の取得が有効であることを意味しない。
_区別する語_: Analytics target

**Earnings acquisition source（決算取得先）**:
分析対象に関連付けられ、決算資料の発見と取得に使う経路。

**Document candidate（資料候補）**:
対象の決算資料に含めるかを検討する取得済み資料。取得だけでは資料種類や対象期間の識別は確定しない。

**Document assessment（資料判定）**:
候補と分析対象の関係や決算資料の種類について、根拠を伴う判断。判定できない場合は候補を確認待ちに残す。

**Operator decision（運用者判断）**:
資料候補を採用・除外する明示的な人間の判断。自動の資料判定とは区別する。

**Earnings release（決算短信）**:
企業が公表する、対象期間の決算の概要。
パイロットでは、URLとは独立に、企業・決算期末・対象期間（第1〜第3四半期または通期）・資料種類で同じ短信を識別する。
_区別する語_: 決算説明資料、有価証券報告書

**Pilot company set（パイロット対象企業）**:
決算情報の収集に使う、運用者が選んだ少数の企業。
_区別する語_: コードに固定した企業一覧、指数の順位

**Original material（原本資料）**:
本文抽出や正規化を行う前の、発行元から取得したままの資料。
_区別する語_: 抽出本文、検索インデックス

**Acquisition time（取得日時）**:
Lensが資料を取得した日時。発行元が示す公開日時とは異なる。
_区別する語_: 公開日時

**Original version（原本の版）**:
取得した原本資料の、バイト列で区別される一つの版。同じバイト列の再取得では新たな版を作らない。
_区別する語_: URL、本文抽出の結果

**Physical storage location（物理保存先）**:
特定の保存バックエンドと不変の保存キーで識別する、原本の版の検証済みコピー。

**Active read location（有効な読取先）**:
一つの原本の版を読む際に現在選択されている物理保存先。選択状態は原本の識別情報とは分けて保存する。

**Acquisition record（取得記録）**:
ある場所から、ある日時に原本資料を取得した記録。複数の取得記録が同じ原本の版を参照することがある。
_区別する語_: 原本の版、公開イベント

**Extracted text（抽出本文）**:
閲覧・検索のために原本の版から生成する本文。同じ原本から再生成できる。
_区別する語_: 原本資料

**Saved search（保存検索）**:
一致する情報を継続して探すために保存した検索条件。
_区別する語_: 収集元の購読設定

**New-publication monitoring（新規公開の監視）**:
保存検索に一致する、新たに公開された情報を見つけること。
_区別する語_: 訂正の検出、前期との業績比較

</details>
