defmodule Lens.ReleaseTest do
  use Lens.DataCase

  alias Lens.Release

  test "preparation accepts only the current schema fingerprint" do
    assert :ok = Release.prepare()
    Repo.query!("UPDATE lens_schema SET fingerprint = 'different-schema'")

    assert_raise RuntimeError, ~r/recreate the disposable database/, fn -> Release.prepare() end
    assert Repo.query!("SELECT fingerprint FROM lens_schema").rows == [["different-schema"]]
  end

  test "initialization refuses an existing schema without changing retained rows" do
    {:ok, source} =
      Lens.Content.create_source(%{
        source_type: "rss",
        endpoint_url: "https://feeds.example.test/current.xml",
        poll_interval_seconds: 300
      })

    assert_raise RuntimeError, ~r/empty database/, fn -> Release.initialize() end
    assert Lens.Repo.get!(Lens.Content.Source, source.id) == source
  end
end
