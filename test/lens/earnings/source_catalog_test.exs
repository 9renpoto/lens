defmodule Lens.Earnings.SourceCatalogTest do
  use Lens.DataCase
  alias Lens.Analysis
  alias Lens.Earnings.{Sources, SourceCatalog}

  test "catalog is empty until an operator registers sources" do
    assert SourceCatalog.all() == []
  end

  test "reads multiple registered routes and current target names with independent enablement" do
    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Synthetic",
        sector: "Test",
        active: false
      })

    {:ok, one} = Sources.create(target, %{listing_url: "https://publisher.invalid/results"})

    {:ok, two} =
      Sources.create(target, %{
        listing_url: "https://publisher.invalid/corrections",
        enabled: false
      })

    sources = SourceCatalog.all()
    assert Enum.sort(Enum.map(sources, & &1.id)) == Enum.sort([one.id, two.id])
    assert Enum.all?(sources, &(&1.issuer_code == "7203" and &1.issuer_name == "Synthetic"))
    assert Enum.map(SourceCatalog.all(enabled_only: true), & &1.id) == [one.id]
    assert SourceCatalog.fetch("7203") == {:error, :multiple_sources}
    assert SourceCatalog.fetch("1234") == {:error, :unsupported_issuer}

    assert Enum.sort(Enum.map(SourceCatalog.for_issuer("7203"), & &1.id)) ==
             Enum.sort([one.id, two.id])

    {:ok, _} = Analysis.update_target(target, %{display_name: "Renamed"})

    {:ok, _} =
      Sources.update(one, %{listing_url: "https://publisher.invalid/new", enabled: false})

    assert SourceCatalog.all(enabled_only: true) == []
    assert Enum.all?(SourceCatalog.all(), &(&1.issuer_name == "Renamed"))

    assert Enum.find(SourceCatalog.all(), &(&1.id == one.id)).listing_url ==
             "https://publisher.invalid/new"
  end
end
