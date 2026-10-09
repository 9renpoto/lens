defmodule Lens.Earnings.StorageFence do
  @moduledoc "Serializes storage changes and durably fences RustFS writers during rollback."
  import Ecto.Query
  alias Lens.Repo

  @lock_class 14_501
  @lock_id 1

  def assert_writable! do
    Repo.query!("SELECT pg_advisory_xact_lock_shared($1, $2)", [@lock_class, @lock_id])

    if rollback_active?(), do: Repo.rollback(:rollback_in_progress)
    :ok
  end

  def with_migration(fun) when is_function(fun, 0) do
    with_exclusive_lock(fn ->
      if rollback_active?(), do: {:error, :rollback_in_progress}, else: fun.()
    end)
  end

  def with_rollback_batch(fun) when is_function(fun, 0) do
    with_exclusive_lock(fn ->
      activate_rollback!()
      result = fun.()

      if complete_rollback?(result) do
        deactivate_rollback!()
      end

      result
    end)
  end

  def rollback_active? do
    case Repo.query!("SELECT to_regclass('earnings_storage_controls') IS NOT NULL").rows do
      [[false]] ->
        false

      [[true]] ->
        Repo.one!(
          from(c in "earnings_storage_controls",
            where: field(c, :id) == 1,
            select: field(c, :rollback_active)
          )
        )
    end
  end

  defp with_exclusive_lock(fun) do
    Repo.checkout(fn ->
      Repo.query!("SELECT pg_advisory_lock($1, $2)", [@lock_class, @lock_id])

      try do
        fun.()
      after
        Repo.query!("SELECT pg_advisory_unlock($1, $2)", [@lock_class, @lock_id])
      end
    end)
  end

  defp activate_rollback! do
    Repo.query!("""
    UPDATE earnings_storage_controls
    SET rollback_active = TRUE,
        rollback_started_at = COALESCE(rollback_started_at, now())
    WHERE id = 1
    """)
  end

  defp deactivate_rollback! do
    Repo.query!("""
    UPDATE earnings_storage_controls
    SET rollback_active = FALSE,
        rollback_started_at = NULL
    WHERE id = 1
    """)
  end

  defp complete_rollback?({:ok, %{complete?: true}}), do: true
  defp complete_rollback?(_), do: false
end
