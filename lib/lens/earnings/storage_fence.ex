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

  def rollback_active? do
    Repo.one!(
      from(c in "earnings_storage_controls",
        where: field(c, :id) == 1,
        select: field(c, :rollback_active)
      )
    )
  end
end
