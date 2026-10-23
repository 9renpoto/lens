defmodule Lens.Investigations.Feed do
  @moduledoc false

  import Saxy.XML, only: [element: 3, characters: 1]

  def render(candidates) do
    channel = [
      text_element("title", "Lens investigation candidates"),
      text_element("link", LensWeb.Endpoint.url() <> "/feeds/investigation-candidates.rss"),
      text_element("description", "Manually registered topics for further investigation.")
    ]

    element("rss", [{"version", "2.0"}], [
      element("channel", [], channel ++ Enum.map(candidates, &item/1))
    ])
    |> Saxy.encode!(version: "1.0", encoding: :utf8)
  end

  defp item(candidate) do
    children = [
      element("guid", [{"isPermaLink", "false"}], characters("urn:uuid:" <> candidate.id)),
      text_element("title", candidate.title),
      text_element("description", escape_html(candidate.body)),
      text_element(
        "pubDate",
        Calendar.strftime(candidate.published_at, "%a, %d %b %Y %H:%M:%S GMT")
      )
    ]

    link = if candidate.details_url, do: [text_element("link", candidate.details_url)], else: []
    element("item", [], children ++ link)
  end

  defp text_element(name, text), do: element(name, [], characters(text))

  # RSS descriptions contain entity-encoded HTML. Keep the supplied body as text.
  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
