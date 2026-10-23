# Run against a local disposable Lens database; this registers one synthetic candidate.
defmodule InvestigationFeedCheck do
  def run(base_url) do
    {:ok, _} = Application.ensure_all_started(:req)
    base_url = String.trim_trailing(base_url, "/")
    feed_url = base_url <> "/feeds/investigation-candidates.rss"
    before = read(feed_url)
    before_ids = MapSet.new(before.entries, & &1.source_entry_id)

    attributes = %{
      title: "RSS verification / 日本語 & evidence",
      body: "Synthetic investigation: <change> & evidence.",
      details_url: "https://example.com/evidence?a=1&b=2",
      published_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    response =
      Req.post!(base_url <> "/api/investigation-candidates", json: %{candidate: attributes})

    check!(response.status == 201, "registration returned HTTP #{response.status}")
    candidate = response.body["candidate"]
    guid = "urn:uuid:" <> candidate["id"]

    first = read(feed_url)
    second = read(feed_url)
    new_entries = Enum.reject(first.entries, &MapSet.member?(before_ids, &1.source_entry_id))
    check!(Enum.map(new_entries, & &1.source_entry_id) == [guid], "expected exactly one new GUID")
    check!(first.xml == second.xml, "feed changed across repeated reads")
    [entry] = new_entries
    check!(entry.title == attributes.title, "consumer title mismatch")
    check!(entry.content == attributes.body, "consumer body mismatch")
    check!(entry.canonical_url == attributes.details_url, "consumer link mismatch")

    check!(
      DateTime.to_iso8601(entry.published_at) == attributes.published_at,
      "publication time mismatch"
    )

    # OTP's XML parser is independent of Saxy, which generates the feed.
    {root, []} = :xmerl_scan.string(:binary.bin_to_list(first.xml), quiet: true)
    check!(value(~c"string(/rss/@version)", root) == "2.0", "expected RSS 2.0")

    for path <- [
          ~c"string(/rss/channel/title)",
          ~c"string(/rss/channel/link)",
          ~c"string(/rss/channel/description)"
        ] do
      check!(value(path, root) != "", "missing channel metadata")
    end

    items = :xmerl_xpath.string(~c"/rss/channel/item", root)
    matching = Enum.filter(items, &(value(~c"string(guid)", &1) == guid))
    check!(length(matching) == 1, "expected one matching XML item")
    [item] = matching
    check!(value(~c"string(guid/@isPermaLink)", item) == "false", "GUID must not be a permalink")
    check!(value(~c"string(title)", item) == attributes.title, "XML title mismatch")
    check!(value(~c"string(link)", item) == attributes.details_url, "XML link mismatch")

    check!(
      value(~c"string(description)", item) =~ "&lt;change&gt;",
      "body must remain text in HTML descriptions"
    )

    IO.puts(
      "PASS: RSS 2.0 parsed by OTP xmerl; one new item detected by Lens RSS consumer; repeated reads stable"
    )

    IO.puts("candidate_id=#{candidate["id"]} guid=#{guid}")
  end

  defp read(url) do
    response = Req.get!(url, headers: [{"accept", "application/rss+xml"}], decode_body: false)
    check!(response.status == 200, "feed returned HTTP #{response.status}")

    check!(
      Enum.any?(
        Req.Response.get_header(response, "content-type"),
        &String.starts_with?(&1, "application/rss+xml")
      ),
      "incorrect RSS content type"
    )

    {:ok, entries} = Lens.Ingestion.Parser.parse(response.body, url)
    %{xml: response.body, entries: entries}
  end

  defp value(path, root) do
    {:xmlObj, :string, text} = :xmerl_xpath.string(path, root)
    List.to_string(text)
  end

  defp check!(true, _message), do: :ok
  defp check!(false, message), do: raise(message)
end

case System.argv() do
  [base_url] ->
    InvestigationFeedCheck.run(base_url)

  _ ->
    raise "Usage: mix run --no-start scripts/check_investigation_feed.exs http://127.0.0.1:4000"
end
