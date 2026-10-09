defmodule Lens.Earnings.StorageRollbackCLITest do
  use ExUnit.Case, async: true

  alias Lens.Earnings.StorageRollbackCLI

  test "accepts a bounded rollback batch and optional UUID cursor" do
    cursor = Ecto.UUID.generate()

    assert {:ok, options} =
             StorageRollbackCLI.validate(["--limit", "25", "--after", cursor])

    assert options[:limit] == 25
    assert options[:after] == cursor

    assert {:ok, [limit: 10]} = StorageRollbackCLI.validate([])
  end

  test "rejects invalid bounds, cursors, duplicate and unknown options" do
    for args <- [
          ["--limit", "0"],
          ["--limit", "101"],
          ["--limit", "many"],
          ["--after", "not-a-uuid"],
          ["--limit", "1", "--limit", "2"],
          ["--copy"],
          ["unexpected"]
        ] do
      assert {:error, :invalid_options} = StorageRollbackCLI.validate(args)
    end
  end
end
