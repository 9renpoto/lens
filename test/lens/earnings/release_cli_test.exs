defmodule Lens.Earnings.ReleaseCLITest do
  use Lens.DataCase
  import ExUnit.CaptureIO

  test "rejects invalid release commands before starting database services" do
    assert {:error, :invalid_options} = Lens.Earnings.ReleaseCLI.validate(["--regenerate"])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate(["--regenerate", "--limit", "101"])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate(["--retry", "not-a-uuid"])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate(["--original", Ecto.UUID.generate(), "extra"])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate([
               "--original",
               Ecto.UUID.generate(),
               "--original",
               Ecto.UUID.generate()
             ])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate([
               "--original",
               Ecto.UUID.generate(),
               "--limit",
               "1"
             ])

    assert {:error, :invalid_options} =
             Lens.Earnings.ReleaseCLI.validate([
               "--regenerate",
               "--limit",
               "1",
               "--after-original",
               "bad"
             ])
  end

  test "validates all bounded release commands and blocks a running application" do
    id = Ecto.UUID.generate()

    assert {:ok, {:original, ^id, original_options}} =
             Lens.Earnings.ReleaseCLI.validate(["--original", id])

    assert Keyword.fetch!(original_options, :original) == id

    assert {:ok, {:retry, ^id, retry_options}} =
             Lens.Earnings.ReleaseCLI.validate(["--retry", id])

    assert Keyword.fetch!(retry_options, :retry) == id

    assert {:ok, {:regenerate, options}} =
             Lens.Earnings.ReleaseCLI.validate([
               "--regenerate",
               "--limit",
               "10",
               "--after-original",
               id
             ])

    assert Keyword.get(options, :after_original) == id
    assert {:error, message} = Lens.Earnings.ReleaseCLI.run(["--", "--original", id])
    assert message =~ "without app.start"
  end

  test "formats CLI errors and failed batch results" do
    assert Lens.Earnings.ReleaseCLI.usage() =~ "--original UUID"

    assert Lens.Earnings.ReleaseCLI.error_message(:invalid_options) ==
             Lens.Earnings.ReleaseCLI.usage()

    assert Lens.Earnings.ReleaseCLI.error_message(:not_found) == "not_found"

    assert Lens.Earnings.ReleaseCLI.error_message("repository unavailable") ==
             "repository unavailable"

    assert Lens.Earnings.ReleaseCLI.render_result({:error, :not_found}) == %{error: "not_found"}

    error =
      capture_io(:stderr, fn ->
        assert :halted =
                 Lens.Earnings.ReleaseCLI.main(["--unknown"], fn 1 -> :halted end)
      end)

    assert error =~ Lens.Earnings.ReleaseCLI.usage()
  end
end
