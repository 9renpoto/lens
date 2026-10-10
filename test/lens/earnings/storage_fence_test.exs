defmodule Lens.Earnings.StorageFenceTest do
  use Lens.DataCase

  alias Lens.Earnings.StorageFence

  test "allows PostgreSQL writes before the storage control migration exists" do
    Repo.query!("SET LOCAL search_path TO pg_temp")

    assert :ok = StorageFence.assert_writable!()
  end
end
