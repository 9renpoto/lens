defmodule Lens.Ingestion.HTMLMaterial do
  @moduledoc "Derives text and source references from one identifiable page scope."
  alias Lens.Ingestion.Normalizer

  @discard "script,style,nav,header,footer,form,noscript,svg"
  @headings ~w(h1 h2 h3 h4 h5 h6)

  def parse(bytes, url, entry, metadata) do
    with true <- String.valid?(bytes),
         {:ok, tree} <- Floki.parse_document(bytes),
         {:ok, selected, locator} <- select(tree, url, entry, metadata) do
      selected = Floki.filter_out(selected, @discard)

      text = selected |> Floki.raw_html() |> Normalizer.text()

      base =
        case Floki.find(tree, "base[href]") |> Floki.attribute("href") do
          [href | _] -> Normalizer.reference_url(href, url) || url
          _ -> url
        end

      links = walk(selected, %{headings: %{}, links: []}, base).links |> Enum.reverse()

      anchors =
        Floki.find(selected, "[id]")
        |> Enum.map(fn {_, attrs, _} = node ->
          id = List.keyfind(attrs, "id", 0) |> elem(1)

          %{
            "fragment" => id,
            "url" =>
              Normalizer.reference_url("#" <> URI.encode(id, &URI.char_unreserved?/1), url),
            "quote" => String.slice(plain(node), 0, 512)
          }
        end)

      cond do
        length(anchors) > 200 ->
          {:error, :too_many_anchors}

        is_nil(text) ->
          {:error, :empty_output}

        length(links) > 200 ->
          {:error, :too_many_links}

        true ->
          {:ok,
           %{
             text: text,
             provenance:
               Map.merge(locator, %{
                 "links" => links,
                 "anchors" => anchors,
                 "headings" =>
                   Floki.find(selected, Enum.join(@headings, ","))
                   |> Enum.take(100)
                   |> Enum.map(&plain/1),
                 "quote" => String.slice(text, 0, 512),
                 "extractor" => "html-text-v1"
               })
           }}
      end
    else
      false -> {:error, :invalid_html}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :ambiguous_material}
  end

  defp select(tree, url, entry, metadata) do
    fragment = URI.parse(Map.get(entry, :entry_url) || url).fragment || URI.parse(url).fragment
    selector = metadata["html_selector"]

    cond do
      is_binary(fragment) and fragment != "" ->
        id = URI.decode(fragment)

        matches =
          Floki.find(tree, "[id]") |> Enum.filter(fn {_, attrs, _} -> {"id", id} in attrs end)

        one(matches, %{"fragment" => fragment})

      is_binary(selector) and selector != "" ->
        one(Floki.find(tree, selector), %{"selector" => selector})

      true ->
        case Floki.find(tree, "article") do
          [article] ->
            titles = Floki.find([article], "h1")

            if length(titles) == 1 and same_title?(plain(hd(titles)), Map.get(entry, :title)) and
                 unambiguous_pdfs?(article, url),
               do:
                 {:ok, [article], %{"selector" => "article", "association" => "matching_title"}},
               else: {:error, :ambiguous_material}

          _ ->
            {:error, :ambiguous_material}
        end
    end
  end

  defp unambiguous_pdfs?(article, base) do
    Floki.find([article], "a[href]")
    |> Enum.flat_map(fn {_, attrs, _} ->
      href = List.keyfind(attrs, "href", 0) |> elem(1)
      type = List.keyfind(attrs, "type", 0, {nil, nil}) |> elem(1)
      url = Normalizer.reference_url(href, base)

      if url &&
           (type == "application/pdf" or
              String.ends_with?(String.downcase(URI.parse(url).path || ""), ".pdf")),
         do: [URI.to_string(%{URI.parse(url) | fragment: nil})],
         else: []
    end)
    |> Enum.uniq()
    |> length()
    |> Kernel.<=(1)
  end

  defp one([node], locator), do: {:ok, [node], locator}
  defp one(_, _), do: {:error, :ambiguous_material}
  defp same_title?(_a, b) when not is_binary(b), do: false

  defp same_title?(a, b),
    do: String.downcase(a) == b |> String.split() |> Enum.join(" ") |> String.downcase()

  defp walk(nodes, state, base) do
    Enum.reduce_while(nodes, state, fn node, acc ->
      if length(acc.links) > 200, do: {:halt, acc}, else: {:cont, visit(node, acc, base)}
    end)
  end

  defp visit({tag, _, children} = node, state, base) when tag in @headings do
    level = String.to_integer(String.last(tag))

    headings =
      state.headings |> Map.reject(fn {key, _} -> key >= level end) |> Map.put(level, plain(node))

    walk(children, %{state | headings: headings}, base)
  end

  defp visit({"a", attrs, children} = node, state, base) do
    url = Normalizer.reference_url(List.keyfind(attrs, "href", 0, {nil, nil}) |> elem(1), base)

    state =
      if url do
        text = plain(node) |> String.slice(0, 512)

        link = %{
          "url" => url,
          "anchor_text" => text,
          "fragment" => URI.parse(url).fragment,
          "headings" => state.headings |> Enum.sort() |> Enum.map(&elem(&1, 1)),
          "quote" => text,
          "type" => List.keyfind(attrs, "type", 0, {nil, nil}) |> elem(1)
        }

        %{state | links: [link | state.links]}
      else
        state
      end

    walk(children, state, base)
  end

  defp visit({_, _, children}, state, base), do: walk(children, state, base)
  defp visit(_, state, _), do: state

  defp plain(node) do
    text = node |> List.wrap() |> Floki.raw_html() |> Normalizer.text()
    (text || "") |> String.split() |> Enum.join(" ") |> String.slice(0, 1000)
  end
end
