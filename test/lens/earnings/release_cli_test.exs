defmodule Lens.Earnings.ReleaseCLITest do
  use ExUnit.Case, async: true

  test "rejects invalid release commands before starting database services" do
    assert {:error, :invalid_options} = Lens.Earnings.ReleaseCLI.validate(["--regenerate"])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate(["--regenerate", "--limit", "101"])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate(["--retry", "not-a-uuid"])
  end
end
