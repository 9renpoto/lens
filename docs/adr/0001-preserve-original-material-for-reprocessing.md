---
status: accepted
---

# Preserve official original material for reprocessing

For the planned earnings-disclosure collection capability, preserve official
original material together with its acquisition URL and acquisition time, and
make searchable text regenerable from that retained material. Keeping only a
link or extracted text would prevent reliable reprocessing if the source
disappears or text extraction needs improvement; retaining originals introduces
storage and recovery responsibilities in exchange for that capability.

## Scope

This records the planning decisions agreed on 2026-09-15. The preservation,
extraction, and search foundations are implemented on `main` as of `5bdd33b`;
source activation, integrated daily/manual collection, complete operator
API/CLI access, and restore verification remain tracked by [#68](https://github.com/9renpoto/lens/issues/68).
It does not redefine existing feed Documents or claim that historical feed
responses have been retained. Identify a logical earnings release by
company, fiscal year-end, reporting period (Q1, Q2, Q3, or full year), and material
category, independent of URL. Keep ambiguous identities pending confirmation
rather than merging them automatically.
The pilot stores originals in PostgreSQL as recorded in
[ADR 0002](0002-store-pilot-originals-in-postgresql.md).

## Preservation and processing boundaries

Retain each distinct original acquired, including changed bytes acquired from
the same URL, without overwriting earlier originals. Reacquiring identical bytes
retains acquisition history without storing a duplicate original. This is
preservation of versions Lens actually acquires, not a guarantee of observing
every publisher edit or an obligation to compare or notify about revisions.

Acquisition success and text-extraction success are separate outcomes. Keep an
acquired original when extraction fails and allow extraction to be retried from
it. The initial release supports text extraction from text-bearing PDFs; OCR is
deferred. An extraction failure must not be represented as successful generation
of searchable text.

## Search projection

Ordinary search returns one result per earnings release, using the latest
original version whose text extraction succeeded. Historical originals remain
accessible from its detail view. If extraction of a newer original fails, make
it explicit that the searchable text belongs to an older version; do not
silently present older text as the newest acquired material.

<details>
<summary>日本語</summary>

# 再処理のために公式の原本資料を保存する

計画中の決算情報収集では、公式の原本資料を取得元URL・取得日時とともに保存し、保存した原本から検索用本文を再生成できるようにする。リンクや抽出本文だけを残す方法では、取得元の消失や本文抽出の改善時に確実な再処理ができない。原本を保持するための保存・復元の責任を引き受けることで、再処理できる状態を確保する。

## 適用範囲

これは2026-09-15に合意した決定を記録する。原本保存・本文抽出・検索の基盤は`main`の`5bdd33b`時点で実装済み。取得元の有効化、一体化した日次・手動収集、運用者向けAPI・CLIの完成、復元検証は[#68](https://github.com/9renpoto/lens/issues/68)で追跡する。既存のフィード由来のDocumentを再定義せず、過去のフィード応答が保存済みであるとも扱わない。論理的に同じ決算短信は、URLとは独立に、企業・決算期末・対象期間（第1〜第3四半期または通期）・資料種類で識別する。識別が曖昧な資料は自動統合せず確認待ちにする。パイロットの原本保存先は、[ADR 0002](0002-store-pilot-originals-in-postgresql.md)に従いPostgreSQLとする。

## 保存と処理の境界

同じURLから異なるバイト列を取得した場合も含め、取得した異なる原本を上書きせず保持する。同じバイト列の再取得では原本を重複保存せず、取得履歴を残す。これはLensが実際に取得した版を保存する方針であり、発行元のすべての変更の検出や、訂正の比較・通知を保証するものではない。

原本の取得成功と本文抽出の成功は別の結果として扱う。本文抽出に失敗しても取得済みの原本を保持し、そこから抽出を再試行できるようにする。初期リリースでは文字情報を持つPDFの本文抽出に対応し、OCRは後続に分ける。抽出失敗を、検索用本文の生成成功として記録してはならない。

## 検索用の表現

通常の検索では、決算短信ごとに、本文抽出に成功した最新の原本の版を使って1件を返す。過去の原本は詳細から参照できるようにする。新しい原本の本文抽出に失敗した場合は、検索対象の本文が旧版に属することを明示し、古い本文を最新の取得資料として表示しない。

</details>
