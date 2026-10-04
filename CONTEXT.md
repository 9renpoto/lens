# Lens

Lens is a personal web observatory for collecting, preserving, searching, and
discovering information over time.

## Language

**Earnings release**:
A company's published summary of its financial results for a reporting period.
In the pilot, its identity is the company, fiscal year-end, reporting period
(Q1, Q2, Q3, or full year), and material category, independent of its URL.
_Avoid_: Earnings presentation, annual securities report

**Pilot company set**:
The fixed set of three companies selected by Nikkei 225 index weight on a
recorded reference date for the initial earnings-collection evaluation.
_Avoid_: Dynamic watchlist, daily contribution ranking

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

**Earnings release（決算短信）**:
企業が公表する、対象期間の決算の概要。
パイロットでは、URLとは独立に、企業・決算期末・対象期間（第1〜第3四半期または通期）・資料種類で同じ短信を識別する。
_区別する語_: 決算説明資料、有価証券報告書

**Pilot company set（パイロット対象企業）**:
決算情報の初期収集評価に使う、記録された基準日の日経平均構成比率で選定した固定3社。
_区別する語_: 動的な監視対象一覧、当日の騰落寄与度ランキング

**Original material（原本資料）**:
本文抽出や正規化を行う前の、発行元から取得したままの資料。
_区別する語_: 抽出本文、検索インデックス

**Acquisition time（取得日時）**:
Lensが資料を取得した日時。発行元が示す公開日時とは異なる。
_区別する語_: 公開日時

**Original version（原本の版）**:
取得した原本資料の、バイト列で区別される一つの版。同じバイト列の再取得では新たな版を作らない。
_区別する語_: URL、本文抽出の結果

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
