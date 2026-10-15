---
status: accepted
---

# Defer backups for disposable development data

Current Lens development data may be lost and recreated, including source registrations. Defer coordinated backup/restore implementation until non-disposable originals or history will be retained, or an operator explicitly requires preservation. Reassess that need under [#173](https://github.com/9renpoto/lens/issues/173) before choosing the minimum implementation; the earlier decomposition in #147 and #169–#172 is no longer an immediate implementation requirement. This accepts loss of current development data in exchange for avoiding operational machinery without an established preservation need.

Manual operation and downtime are acceptable starting preferences, with no fixed recovery-point objective today. Backup format, writer-fencing mechanism, retention and restore procedures remain undecided. [ADR 0005](0005-store-pdfs-in-rustfs.md) still defines coordinated recovery for data that must be preserved; this timing decision does not establish backup integrity or completed restore verification. Source/assessment workflow verification remains #131, with broader release verification under #74.

<details>
<summary>日本語</summary>

# 破棄可能な開発データのバックアップは後回しにする

現在のLens開発データは、取得先登録を含め、失って再作成してよいものとする。破棄できない原本・履歴を保持し始める前、または運用者が保持を明示的に求めるまで、協調バックアップ・復元の実装を後回しにする。[#173](https://github.com/9renpoto/lens/issues/173)で必要性を再評価してから最小の実装を選び、先行して分割した#147・#169〜#172は直ちに実装する要件としない。保持の必要性が成立していない運用機構を作らない代わりに、現在の開発データの損失を受け入れる。

現時点の出発点は手動操作・停止許容・固定の復旧時点目標なしとする。バックアップ形式、writer停止の仕組み、保持期間、復元手順は未決定。[ADR 0005](0005-store-pdfs-in-rustfs.md)の協調復旧方針は保持が必要なデータに引き続き適用し、この時期の判断だけでバックアップの整合や復元検証の完了とはしない。取得先・判定フローの検証は#131、広範なリリース検証は#74に残る。

</details>
