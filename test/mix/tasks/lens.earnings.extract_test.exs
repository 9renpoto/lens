defmodule Mix.Tasks.Lens.Earnings.ExtractTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Lens.Earnings.Extract

  test "rejects unbounded regeneration and ambiguous commands before starting services" do
    for args <- [
          [],
          ["--regenerate"],
          ["--regenerate", "--limit", "0"],
          ["--regenerate", "--limit", "101"],
          ["--retry", "invalid"],
          ["--original", Ecto.UUID.generate(), "--regenerate", "--limit", "1"],
          ["--unknown"]
        ] do
      assert_raise Mix.Error, fn -> Extract.run(args) end
    end
  end
end
