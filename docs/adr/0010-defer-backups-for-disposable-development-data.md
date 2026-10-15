---
status: accepted
---

# Defer backups until value is established

Lens development and test data may be changed destructively or deleted through the v1 development release. Value validation after v1 may use real earnings data only in a development or test environment where those records are explicitly designated disposable; they may be deleted after validation. This allowance does not apply to data designated for preservation or to production operation. Before retaining non-disposable records or operating Lens in production, follow [ADR 0005](0005-store-pdfs-in-rustfs.md) and [the deployment requirements](../deployment.md), including coordinated PostgreSQL/RustFS backup and recovery. Track the v1 review and value-validation sequence in [#173](https://github.com/9renpoto/lens); #147 and #169–#172 remain closed as not planned.

When value validation shows that records should be retained, define the minimum backup and recovery work needed for that scope. Manual operation and downtime remain acceptable starting preferences, with no fixed recovery-point objective. Decide the backup format, writer-fencing mechanism, retention and restore evidence then. This ADR does not waive existing production backup requirements or establish backup integrity or completed restore verification. Source/assessment workflow verification remains #131, with broader release verification under #74.

<details>
<summary>日本語</summary>

# 価値が確認できるまでバックアップを後回しにする

Lensの開発・テストデータは、開発環境でのv1リリースまでは破壊的変更や全削除を許容する。v1後の価値検証で実際の決算データを使う場合も、開発・テスト環境で明示的に破棄可能とした記録だけを対象にし、検証後の削除を許容する。この許容は、保持対象に指定したデータや本番運用には適用しない。破棄できない記録の保持開始前または本番運用前には、[ADR 0005](0005-store-pdfs-in-rustfs.md)と[デプロイ要件](../deployment.md)に従い、PostgreSQL/RustFSの協調バックアップ・復旧を含む既存要件を満たす。v1前の確認と価値検証の順序は[#173](https://github.com/9renpoto/lens/issues/173)で追跡し、#147・#169〜#172はnot plannedでクローズしたままとする。

価値検証で記録を保持する必要が確認されたら、その範囲に必要な最小のバックアップ・復旧作業を定める。現時点の出発点は手動操作・停止許容・固定の復旧時点目標なしとする。バックアップ形式、writer停止の仕組み、保持期間、復元の証跡はその時点で決める。本ADRは既存の本番バックアップ要件を免除せず、バックアップの整合や復元検証の完了も意味しない。取得先・判定フローの検証は#131、広範なリリース検証は#74に残る。

</details>
