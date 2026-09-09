defmodule Mix.Tasks.Lens.Search.RebuildTest do
  use Lens.DataCase

  import ExUnit.CaptureIO

  test "rebuilds search data with a bounded batch size" do
    Mix.Task.reenable("lens.search.rebuild")

    assert capture_io(fn -> Mix.Tasks.Lens.Search.Rebuild.run(["--batch-size", "1"]) end) ==
             "Search data rebuilt.\n"
  end

  test "rejects unsupported arguments" do
    assert_raise Mix.Error,
                 "usage: mix lens.search.rebuild [--batch-size POSITIVE_INTEGER]",
                 fn ->
                   Mix.Tasks.Lens.Search.Rebuild.run(["--unknown"])
                 end
  end

  test "rejects a non-positive batch size" do
    assert_raise Mix.Error, "batch size must be a positive integer", fn ->
      Mix.Tasks.Lens.Search.Rebuild.run(["--batch-size", "0"])
    end
  end
end
