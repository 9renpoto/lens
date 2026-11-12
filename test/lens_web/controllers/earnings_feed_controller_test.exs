defmodule LensWeb.EarningsFeedControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest

  alias Lens.{Analysis, StorageFixtures}
  alias Lens.Earnings.{Acquisition, Extraction, Extractions, Original, Release}

  @endpoint LensWeb.Endpoint

  setup do
    {:ok, target} = target("SYNTHETIC_ISSUER_A")
    %{target: target}
  end

  defp target(code) do
    Analysis.create_target(%{
      security_code: code,
      display_name: "Synthetic Issuer & <group>",
      market: "synthetic",
      sector: "synthetic",
      active: false
    })
  end

  defp retain(target, key, options \\ []) do
    {:ok, retained} =
      StorageFixtures.record_success(%{
        bytes: Keyword.get(options, :bytes, "%PDF-synthetic-#{key}"),
        acquisition_id: key,
        issuer_code: target.security_code,
        acquired_at: DateTime.add(~U[2030-01-01 00:00:00.000000Z], Keyword.get(options, :at, 0)),
        url: "https://publisher.invalid/#{key}.pdf",
        release:
          Keyword.get(options, :release, %{
            fiscal_year_end: ~D[2030-03-31],
            period: "q1",
            category: "earnings_release"
          })
      })

    retained
  end

  defp extract(original_id, text) do
    {:ok, pending} = Extractions.begin(original_id, "synthetic", "1")
    {:ok, extraction} = Extractions.succeed(pending.id, text)
    extraction
  end

  defp read() do
    conn =
      build_conn()
      |> Plug.Conn.put_req_header("accept", "application/rss+xml")
      |> get("/feeds/earnings.rss")

    assert Plug.Conn.get_resp_header(conn, "content-type") == [
             "application/rss+xml; charset=utf-8"
           ]

    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"]
    response(conn, 200)
  end

  defp channel(xml) do
    assert {:ok, {"rss", [{"version", "2.0"}], [{"channel", [], children}]}} =
             Saxy.SimpleForm.parse_string(xml)

    children
  end

  defp items(xml), do: for({"item", _, children} <- channel(xml), do: children)

  defp value(children, name) do
    case List.keyfind(children, name, 0) do
      {_, _, [text]} -> text
      nil -> nil
    end
  end

  defp plain_body(item) do
    item |> value("description") |> Floki.parse_fragment!() |> Floki.text(sep: "")
  end

  test "the service feed has a valid empty RSS channel without eligible items" do
    xml = read()
    assert items(xml) == []

    for tag <- ["title", "link", "description"],
        do: assert(value(channel(xml), tag) not in [nil, ""])

    assert {_, []} = :xmerl_scan.string(:binary.bin_to_list(xml), quiet: true)
  end

  test "the former target-specific URL is unavailable", %{target: target} do
    conn = get(build_conn(), "/feeds/targets/#{target.id}/earnings.rss")
    assert response(conn, 404)
  end

  test "the full stored text, generated title and matching original link are readable", %{
    target: target
  } do
    retained = retain(target, "full-text")

    text =
      "日本語 & <script>alert('synthetic')</script>\n  aligned text\n" <>
        String.duplicate("Complete text. ", 50)

    extract(retained.original.id, text)
    xml = read()
    assert [item] = items(xml)
    assert value(item, "title") == "Synthetic Issuer & <group> 2030年3月期 第1四半期 決算短信"
    assert value(item, "guid") == "urn:uuid:" <> retained.release.id
    assert {"guid", [{"isPermaLink", "false"}], _} = List.keyfind(item, "guid", 0)
    assert plain_body(item) == text

    assert value(item, "link") ==
             LensWeb.Endpoint.url() <> "/api/earnings/originals/" <> retained.original.id

    refute value(item, "pubDate")
    assert xml == read()
    assert {_, []} = :xmerl_scan.string(:binary.bin_to_list(xml), quiet: true)
    parsed = Floki.parse_fragment!(value(item, "description"))
    assert Floki.find(parsed, "script") == []

    original =
      build_conn()
      |> Plug.Conn.put_req_header("accept", "application/pdf")
      |> get("/api/earnings/originals/#{retained.original.id}")

    assert response(original, 200) == "%PDF-synthetic-full-text"
  end

  test "confirmed releases with successful text are published across targets", %{
    target: target
  } do
    included = retain(target, "included")
    extract(included.original.id, "Included text")

    retain(target, "pending",
      release: %{fiscal_year_end: ~D[2030-03-31], period: "q2", category: "earnings_release"}
    )

    failed =
      retain(target, "failed",
        release: %{fiscal_year_end: ~D[2030-03-31], period: "q3", category: "earnings_release"}
      )

    {:ok, attempt} = Extractions.begin(failed.original.id, "synthetic", "1")
    {:ok, _} = Extractions.fail(attempt.id, "synthetic_failure")
    unknown = retain(target, "unconfirmed", release: nil)
    extract(unknown.original.id, "Unconfirmed text")
    {:ok, other_target} = target("SYNTHETIC_ISSUER_B")
    other = retain(other_target, "other")
    extract(other.original.id, "Other issuer")

    counts =
      for schema <- [Acquisition, Original, Release, Extraction],
          do: Repo.aggregate(schema, :count)

    entries = items(read())

    assert MapSet.new(Enum.map(entries, &value(&1, "guid"))) ==
             MapSet.new(["urn:uuid:" <> included.release.id, "urn:uuid:" <> other.release.id])

    assert MapSet.new(Enum.map(entries, &plain_body/1)) ==
             MapSet.new(["Included text", "Other issuer"])

    assert counts ==
             for(
               schema <- [Acquisition, Original, Release, Extraction],
               do: Repo.aggregate(schema, :count)
             )
  end

  test "a shared original produces separate stable items for separate releases", %{target: target} do
    first = retain(target, "shared-first", bytes: "%PDF-synthetic-shared")

    second =
      retain(target, "shared-second",
        bytes: "%PDF-synthetic-shared",
        at: 60,
        release: %{fiscal_year_end: ~D[2030-03-31], period: "q2", category: "earnings_release"}
      )

    assert first.original.id == second.original.id
    extract(first.original.id, "Shared text")
    xml = read()
    entries = items(xml)
    assert length(entries) == 2

    assert Enum.sort(Enum.map(entries, &value(&1, "guid"))) ==
             Enum.sort(["urn:uuid:" <> first.release.id, "urn:uuid:" <> second.release.id])

    assert Enum.uniq(Enum.map(entries, &value(&1, "link"))) == [
             LensWeb.Endpoint.url() <> "/api/earnings/originals/" <> first.original.id
           ]

    assert xml == read()
  end

  test "existing text selection changes content and original link under the same release GUID", %{
    target: target
  } do
    old = retain(target, "old")
    extract(old.original.id, "Old successful text")
    newer = retain(target, "newer", at: 60)
    assert newer.release.id == old.release.id
    assert [item] = items(read())
    assert plain_body(item) == "Old successful text"
    extract(newer.original.id, "New successful text")
    assert [updated] = items(read())
    assert value(updated, "guid") == value(item, "guid")
    assert plain_body(updated) == "New successful text"

    assert value(updated, "link") ==
             LensWeb.Endpoint.url() <> "/api/earnings/originals/" <> newer.original.id

    extract(old.original.id, "Late extraction of old original")
    assert [current] = items(read())
    assert plain_body(current) == "New successful text"
  end

  test "stored form-feed characters remain text without producing invalid XML", %{target: target} do
    retained = retain(target, "control")
    text = "First page\fSecond page\r\nTail"
    extract(retained.original.id, text)
    xml = read()
    assert {_, []} = :xmerl_scan.string(:binary.bin_to_list(xml), quiet: true)
    assert [item] = items(xml)
    assert plain_body(item) == text
  end

  test "repeated successful acquisitions do not duplicate a release item", %{target: target} do
    first = retain(target, "repeat-first", bytes: "%PDF-synthetic-repeated")
    second = retain(target, "repeat-second", bytes: "%PDF-synthetic-repeated", at: 60)
    assert first.release.id == second.release.id
    assert first.original.id == second.original.id
    extract(first.original.id, "Repeated acquisition text")
    assert [item] = items(read())
    assert value(item, "guid") == "urn:uuid:" <> first.release.id
  end

  test "the renderer emits publication dates only for complete timestamps" do
    entry = %{
      link: "http://localhost/original.pdf",
      guid: "urn:uuid:00000000-0000-4000-8000-000000000001",
      title: "Synthetic title",
      content: "Synthetic text",
      published_at: nil
    }

    for date <- [nil, ~D[2030-01-01], ~N[2030-01-01 09:02:03]] do
      xml = Lens.Earnings.Feed.render([%{entry | published_at: date}], "http://localhost")
      assert [item] = items(xml)
      refute value(item, "pubDate")
    end

    {:ok, datetime, _} = DateTime.from_iso8601("2030-01-01T09:02:03+09:00")
    xml = Lens.Earnings.Feed.render([%{entry | published_at: datetime}], "http://localhost")
    assert [item] = items(xml)
    assert value(item, "pubDate") == "Tue, 01 Jan 2030 00:02:03 GMT"
  end

  test "OpenAPI documents only the service RSS route" do
    document = LensWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()
    operation = document["paths"]["/feeds/earnings.rss"]["get"]
    assert operation["responses"]["200"]["content"]["application/rss+xml"]
    refute Map.has_key?(document["paths"], "/feeds/targets/{target_id}/earnings.rss")
  end
end
