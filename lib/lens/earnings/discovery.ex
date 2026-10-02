defmodule Lens.Earnings.Discovery do
  @moduledoc "Discover actual PDF anchors without inferring identity or fetching publisher material."

  @max_listing_bytes 2_097_152
  @max_links 200

  @doc "Resolve PDF anchors against the final listing response URL and retain observed provenance."
  def links(listing_url, html) when is_binary(listing_url) and is_binary(html) do
    cond do
      byte_size(html) > @max_listing_bytes ->
        {:error, :listing_too_large}

      not String.valid?(html) ->
        {:error, :invalid_html}

      not valid_http_url?(listing_url) ->
        {:error, :invalid_listing_url}

      true ->
        parse_links(listing_url, html)
    end
  end

  def links(_, _), do: {:error, :invalid_html}

  defp parse_links(listing_url, html) do
    with {:ok, tree} <- Floki.parse_document(html) do
      state = walk(tree, %{headings: %{}, links: [], seen: MapSet.new(), count: 0}, listing_url)

      if state.count > @max_links,
        do: {:error, :too_many_links},
        else: {:ok, Enum.reverse(state.links)}
    else
      _ -> {:error, :invalid_html}
    end
  end

  defp walk(nodes, state, listing_url) do
    Enum.reduce_while(nodes, state, fn node, acc ->
      if acc.count > @max_links do
        {:halt, acc}
      else
        {:cont, visit(node, acc, listing_url)}
      end
    end)
  end

  defp visit({tag, _, children} = node, state, listing_url) when tag in ~w(h1 h2 h3 h4 h5 h6) do
    level = tag |> String.last() |> String.to_integer()

    headings =
      state.headings
      |> Map.reject(fn {key, _} -> key >= level end)
      |> Map.put(level, text(node))

    walk(children, %{state | headings: headings}, listing_url)
  end

  defp visit({"a", attrs, _} = node, state, listing_url) do
    with {"href", href} <- List.keyfind(attrs, "href", 0),
         {:ok, url, comparison_url} <- resolve_pdf(listing_url, href),
         false <- MapSet.member?(state.seen, comparison_url) do
      link = %{
        href: href,
        url: url,
        comparison_url: comparison_url,
        listing_url: listing_url,
        anchor_text: text(node),
        headings: Enum.sort(state.headings)
      }

      %{
        state
        | links: [link | state.links],
          seen: MapSet.put(state.seen, comparison_url),
          count: state.count + 1
      }
    else
      _ -> state
    end
  end

  defp visit({tag, _, _}, state, _listing_url) when tag in ~w(script style), do: state
  defp visit({_, _, children}, state, listing_url), do: walk(children, state, listing_url)
  defp visit(_, state, _listing_url), do: state

  defp resolve_pdf(listing_url, href) do
    with {:ok, target} <- URI.new(String.trim(href)),
         url <- resolved_url(listing_url, target, href),
         true <- valid_http_url?(url),
         uri <- URI.parse(url),
         true <- String.ends_with?(String.downcase(uri.path || ""), ".pdf") do
      comparison = %{
        uri
        | scheme: String.downcase(uri.scheme),
          host: String.downcase(uri.host),
          fragment: nil
      }

      {:ok, url, URI.to_string(comparison)}
    else
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp resolved_url(_listing_url, %{scheme: scheme}, href) when not is_nil(scheme),
    do: String.trim(href)

  defp resolved_url(listing_url, %{host: host}, href) when not is_nil(host),
    do: URI.parse(listing_url).scheme <> ":" <> String.trim(href)

  defp resolved_url(listing_url, target, _href),
    do: listing_url |> URI.merge(target) |> URI.to_string()

  defp valid_http_url?(url) when is_binary(url) do
    if String.valid?(url) do
      valid_http_uri?(url)
    else
      false
    end
  end

  defp valid_http_url?(_), do: false

  defp valid_http_uri?(url) do
    case URI.new(url) do
      {:ok, %{scheme: scheme, host: host, userinfo: nil}} when is_binary(host) and host != "" ->
        String.downcase(scheme || "") in ["http", "https"]

      _ ->
        false
    end
  end

  defp text(node), do: node |> Floki.text(sep: " ") |> String.split() |> Enum.join(" ")
end
