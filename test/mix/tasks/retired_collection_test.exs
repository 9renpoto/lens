defmodule Mix.Tasks.RetiredCollectionTest do
  use ExUnit.Case, async: true

  test "manual PDF collection is no longer exposed as a Mix task" do
    assert_raise Mix.NoTaskError, fn ->
      Mix.Task.get!("lens.earnings.collect")
    end
  end
end
