defmodule LensWeb.InvestigationFeedControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest

  @endpoint LensWeb.Endpoint
  @feed "/feeds/investigation-candidates.rss"

  defp read_feed do
    conn = build_conn() |> Plug.Conn.put_req_header("accept", "application/rss+xml") |> get(@feed)

    assert Plug.Conn.get_resp_header(conn, "content-type") == [
             "application/rss+xml; charset=utf-8"
           ]

    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"]
    response(conn, 200)
  end

  defp register(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "日本語 & <change>",
          body: "根拠 <script>alert('x')</script> & details",
          published_at: "2026-10-21T09:30:00+09:00"
        },
        overrides
      )

    build_conn()
    |> post("/api/investigation-candidates", candidate: attrs)
    |> json_response(201)
    |> Map.fetch!("candidate")
  end

  defp entries(xml) do
    {:ok, entries} = Lens.Ingestion.Parser.parse(xml, "http://localhost:4000" <> @feed)
    entries
  end

  test "empty feed is a valid RSS 2.0 channel with required metadata" do
    xml = read_feed()

    assert {:ok, {"rss", [{"version", "2.0"}], [{"channel", [], children}]}} =
             Saxy.SimpleForm.parse_string(xml)

    for tag <- ["title", "link", "description"] do
      assert {^tag, [], [value]} = List.keyfind(children, tag, 0)
      assert value != ""
    end

    assert entries(xml) == []
  end

  test "a new candidate is detected once and keeps its GUID and content on repeated reads" do
    before_ids = MapSet.new(entries(read_feed()), & &1.source_entry_id)
    candidate = register(%{details_url: "https://example.com/evidence?a=1&b=2"})
    first = read_feed()
    assert first == read_feed()
    assert [entry] = entries(first)
    assert entry.source_entry_id == "urn:uuid:" <> candidate["id"]
    refute MapSet.member?(before_ids, entry.source_entry_id)
    assert {:ok, {"rss", _, [{"channel", _, children}]}} = Saxy.SimpleForm.parse_string(first)
    {"item", _, item_children} = List.keyfind(children, "item", 0)
    assert {"title", [], ["日本語 & <change>"]} = List.keyfind(item_children, "title", 0)
    assert entry.canonical_url == "https://example.com/evidence?a=1&b=2"
    assert DateTime.compare(entry.published_at, ~U[2026-10-21 00:30:00Z]) == :eq
    assert first =~ "isPermaLink=\"false\""
    assert first =~ "Wed, 21 Oct 2026 00:30:00 GMT"
    assert first =~ "&amp;lt;script&amp;gt;"
    refute first =~ "<script>"
    assert entry.content =~ "<script>alert('x')</script>"

    second = register(%{body: "Another candidate", published_at: "2026-10-22T00:00:00Z"})
    after_entries = entries(read_feed())
    assert length(after_entries) == 2
    assert hd(after_entries).source_entry_id == "urn:uuid:" <> second["id"]
    assert Enum.find(after_entries, &(&1.source_entry_id == entry.source_entry_id)) == entry
  end

  test "a candidate without a URL has no link element and still has a usable identity" do
    candidate = register()
    xml = read_feed()
    assert [entry] = entries(xml)
    assert entry.source_entry_id == "urn:uuid:" <> candidate["id"]
    assert {:ok, {"rss", _, [{"channel", _, children}]}} = Saxy.SimpleForm.parse_string(xml)
    {"item", _, item_children} = List.keyfind(children, "item", 0)
    refute List.keymember?(item_children, "link", 0)
  end

  test "registration exposes no editing or deletion routes" do
    candidate = register()

    for method <- [:patch, :put, :delete] do
      conn =
        dispatch(
          build_conn(),
          @endpoint,
          method,
          "/api/investigation-candidates/#{candidate["id"]}",
          %{}
        )

      assert conn.status == 404
    end

    assert length(entries(read_feed())) == 1
  end
end
