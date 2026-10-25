# Read-only check against an existing retained result inside the private access boundary.
defmodule EarningsFeedCheck do
  def run(base_url, target_id) do
    {:ok, _} = Application.ensure_all_started(:req)
    base_url = String.trim_trailing(base_url, "/")
    feed_url = base_url <> "/feeds/targets/" <> target_id <> "/earnings.rss"
    first = get!(feed_url, "application/rss+xml")
    second = get!(feed_url, "application/rss+xml")
    check!(first.body == second.body, "RSS changed across repeated reads")
    {:ok, entries} = Lens.Ingestion.Parser.parse(first.body, feed_url)
    check!(entries != [], "no eligible retained releases were found")
    ids = Enum.map(entries, & &1.source_entry_id)
    check!(length(ids) == length(Enum.uniq(ids)), "duplicate release GUIDs")

    {:ok, {"rss", [{"version", "2.0"}], [{"channel", [], children}]}} =
      Saxy.SimpleForm.parse_string(first.body)

    {_, []} = :xmerl_scan.string(:binary.bin_to_list(first.body), quiet: true)
    items = for {"item", _, fields} <- children, do: fields
    check!(length(items) == length(entries), "consumer item count mismatch")

    Enum.each(items, fn fields ->
      "urn:uuid:" <> release_id = value(fields, "guid")
      check!(match?({:ok, _}, Ecto.UUID.cast(release_id)), "invalid release GUID")

      check!(
        List.keyfind(fields, "guid", 0) |> elem(1) == [{"isPermaLink", "false"}],
        "GUID is not a stable non-permalink"
      )

      detail = get!(base_url <> "/api/earnings/releases/" <> release_id, "application/json")
      data = Jason.decode!(detail.body)
      extraction = data["extraction"]

      check!(
        is_map(extraction) and extraction["status"] == "succeeded",
        "no successful stored extraction"
      )

      check!(data["release"]["id"] == release_id, "release identity mismatch")
      body = fields |> value("description") |> Floki.parse_fragment!() |> Floki.text(sep: "")
      check!(body == extraction["text"], "RSS text differs from the stored extraction")
      expected_link = base_url <> "/api/earnings/originals/" <> extraction["original_id"]

      check!(
        value(fields, "link") == expected_link,
        "RSS original link does not match selected text"
      )

      original = get!(expected_link, "application/pdf")
      check!(String.starts_with?(original.body, "%PDF-"), "original response is not a PDF")
    end)

    IO.puts(
      "PASS: RSS parsed by Lens and OTP xmerl; #{length(items)} release item(s); stored full text and retained PDF links verified; repeated-read GUIDs stable"
    )
  end

  defp get!(url, content_type) do
    response = Req.get!(url, headers: [{"accept", content_type}], decode_body: false)
    check!(response.status == 200, "read-only request did not return HTTP 200")

    check!(
      Enum.any?(
        Req.Response.get_header(response, "content-type"),
        &String.starts_with?(&1, content_type)
      ),
      "unexpected response content type"
    )

    response
  end

  defp value(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, _, [text]} -> text
      nil -> nil
    end
  end

  defp check!(true, _message), do: :ok
  defp check!(false, message), do: raise(message)
end

case System.argv() do
  [base_url, target_id] -> EarningsFeedCheck.run(base_url, target_id)
  _ -> raise "Usage: mix run --no-start scripts/check_earnings_feed.exs BASE_URL TARGET_ID"
end
