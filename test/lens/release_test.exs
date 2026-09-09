defmodule Lens.ReleaseTest do
  use Lens.DataCase

  alias Lens.Release

  test "runs pending migrations for the configured repository" do
    assert :ok = Release.migrate()
  end
end
