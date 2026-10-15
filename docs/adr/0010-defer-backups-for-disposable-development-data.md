---
status: accepted
---

# Defer backups until value is established

Lens development data may be changed destructively or deleted through v1. Before the v1 release or a move to a production-like environment, review which data would need preservation; record any resulting loss risk without blocking v1. After v1, prioritize value validation: run a complete workflow with real earnings data while accepting that validation data may be discarded. Start the minimum backup and recovery work only if the operator then decides that the results or history are worth retaining. Track this sequence in [#173](https://github.com/9renpoto/lens/issues/173); #147 and #169–#172 remain closed as not planned.

Manual operation and downtime remain acceptable starting preferences, with no fixed recovery-point objective. Decide the backup format, writer-fencing mechanism, retention and restore evidence only when the value signal exists. [ADR 0005](0005-store-pdfs-in-rustfs.md) continues to define coordinated recovery for data that must be preserved; this timing decision does not establish backup integrity or completed restore verification. Source/assessment workflow verification remains #131, with broader release verification under #74.

<details>
<summary>日本語</summary>

# 価値が確認できるまでバックアップを後回しにする

Lensの開発データは、v1までは破壊的に変更したり全削除したりしてよい。v1のリリースまたは本番相当環境への移行前に、保持が必要なデータを確認し、損失リスクが判明した場合も記録したうえでv1を止めない。v1後は価値検証を優先し、実際の決算データで一連の利用フローを試す。検証データも破棄可能とする。運用者が結果や履歴を残す価値があると判断した場合に限り、必要最小限のバックアップ・復旧対応を始める。この順序は[#173](https://github.com/9renpoto/lens/issues/173)で追跡し、#147・#169〜#172はnot plannedでクローズしたままとする。

現時点の出発点は手動操作・停止許容・固定の復旧時点目標なしとする。バックアップ形式、writer停止の仕組み、保持期間、復元の証跡は価値が確認できた段階で決める。[ADR 0005](0005-store-pdfs-in-rustfs.md)の協調復旧方針は保持が必要なデータに引き続き適用し、この時期の判断だけでバックアップの整合や復元検証の完了とはしない。取得先・判定フローの検証は#131、広範なリリース検証は#74に残る。

</details>
