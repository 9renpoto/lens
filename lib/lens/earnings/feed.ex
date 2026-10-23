defmodule Lens.Earnings.Feed do
  @moduledoc "RSS publication of existing selected earnings text."

  import Saxy.XML, only: [element: 3, characters: 1]

  def entries(issuer_code) do
    issuer_code |> Lens.Search.Earnings.feed_query() |> Lens.Repo.all()
  end

  def render(entries, base_url) do
    channel = [
      text_element("title", "Lens retained earnings"),
      text_element("link", base_url <> "/dashboard"),
      text_element(
        "description",
        "Existing extracted earnings text; item titles are generated labels."
      )
    ]

    element("rss", [{"version", "2.0"}], [
      element("channel", [], channel ++ Enum.map(entries, &item(&1, base_url)))
    ])
    |> Saxy.encode!(version: "1.0", encoding: :utf8)
  end

  defp item(entry, base_url) do
    children = [
      element("guid", [{"isPermaLink", "false"}], characters("urn:uuid:" <> entry.id)),
      text_element("title", entry.title),
      text_element("description", "<pre>" <> html_text(entry.content) <> "</pre>"),
      text_element("link", base_url <> "/api/earnings/originals/" <> entry.original_id)
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

    element("item", [], children ++ date)
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
