defmodule Lens.Earnings.Feed do
  @moduledoc "Read-only RSS publication of acquired updates and retained earnings releases."

  import Ecto.Query
  import Saxy.XML, only: [element: 3, characters: 1]

  alias Lens.Ingestion.Material
  alias Lens.Repo
  alias Lens.Search.Earnings

  def entries(base_url), do: release_entries(base_url) ++ update_entries()

  defp release_entries(base_url) do
    Earnings.feed_query()
    |> Repo.all()
    |> Enum.map(fn release ->
      %{
        guid: "urn:uuid:" <> release.id,
        title: release.title,
        content: release.content,
        link: base_url <> "/api/earnings/originals/" <> release.original_id,
        published_at: release.published_at
      }
    end)
  end

  defp update_entries do
    from(material in Material,
      join: extraction in "feed_material_extractions",
      on: extraction.material_id == material.id,
      where: material.kind == "html",
      # Configured selectors record a selector without the title-matching fallback marker.
      where:
        fragment(
          "?->>'selector' IS NOT NULL AND ?->>'association' IS NULL",
          material.provenance,
          material.provenance
        ),
      order_by: [asc: material.acquired_at, asc: material.id],
      select: {material.id, material.entry_snapshot, extraction.text, material.final_url}
    )
    |> Repo.all()
    |> Enum.map(fn {id, entry, text, link} ->
      %{
        guid: "lens:feed-update:" <> id,
        title: entry["title"],
        content: text,
        link: link,
        published_at: publication_time(entry["publisher_published_at"])
      }
    end)
  end

  defp publication_time(date) when is_binary(date) do
    case DateTime.from_iso8601(date) do
      {:ok, time, _offset} -> time
      _ -> nil
    end
  end

  defp publication_time(_), do: nil

  def render(entries, base_url) do
    channel = [
      text_element("title", "Lens retained earnings"),
      text_element("link", base_url <> "/dashboard"),
      text_element("description", "Acquired earnings updates and confirmed releases.")
    ]

    element("rss", [{"version", "2.0"}], [
      element("channel", [], channel ++ Enum.map(entries, &item/1))
    ])
    |> Saxy.encode!(version: "1.0", encoding: :utf8)
  end

  defp item(entry) do
    title = if is_binary(entry.title), do: [text_element("title", entry.title)], else: []

    children = [
      element("guid", [{"isPermaLink", "false"}], characters(entry.guid)),
      text_element("description", "<pre>" <> html_text(entry.content) <> "</pre>"),
      text_element("link", entry.link)
    ]

    date =
      case entry.published_at do
        %DateTime{} = datetime ->
          [
            text_element(
              "pubDate",
              datetime
              |> DateTime.shift_zone!("Etc/UTC")
              |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
            )
          ]

        _ ->
          []
      end

    element("item", [], title ++ children ++ date)
  end

  defp text_element(name, text) do
    safe_text =
      text
      |> String.to_charlist()
      |> Enum.map(fn c -> if xml_character?(c), do: <<c::utf8>>, else: "�" end)
      |> IO.iodata_to_binary()

    element(name, [], characters(safe_text))
  end

  # Entity-encoded HTML preserves the extracted text and page breaks without
  # placing forbidden XML characters or executable publisher markup in the feed.
  defp html_text(text) do
    text
    |> String.to_charlist()
    |> Enum.map(fn
      ?& -> "&amp;"
      ?< -> "&lt;"
      ?> -> "&gt;"
      13 -> "&#13;"
      c -> if xml_character?(c), do: <<c::utf8>>, else: "&#" <> Integer.to_string(c) <> ";"
    end)
    |> IO.iodata_to_binary()
  end

  defp xml_character?(c),
    do: c in [9, 10, 13] or c in 0x20..0xD7FF or c in 0xE000..0xFFFD or c in 0x10000..0x10FFFF
end
