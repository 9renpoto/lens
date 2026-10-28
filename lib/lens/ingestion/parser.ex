defmodule Lens.Ingestion.Parser do
  alias Lens.Ingestion.Normalizer

  @rss_1_0_namespace "http://purl.org/rss/1.0/"

  @typedoc "A feed entry normalized before persistence."
  @type entry :: %{
          source_entry_id: String.t() | nil,
          canonical_url: String.t() | nil,
          title: String.t() | nil,
          content: String.t() | nil,
          author: String.t() | nil,
          published_at: DateTime.t() | nil,
          entry_url: String.t() | nil,
          updated_at: DateTime.t() | nil,
          raw_content: String.t() | nil,
          attachments: [map()],
          body_links: [String.t()],
          feed_fingerprint: String.t()
        }

  @spec parse(binary(), String.t()) :: {:ok, [entry()]} | {:error, String.t()}
  def parse(xml, endpoint_url) when is_binary(xml) do
    with {:ok, root} <- Saxy.SimpleForm.parse_string(xml, cdata_as_characters: true),
         {:ok, kind} <- feed_kind(root) do
      {:ok, entries(root, kind, endpoint_url)}
    else
      {:error, error} -> {:error, message(error)}
    end
  end

  defp feed_kind({name, attributes, _} = root) do
    case local_name(name) do
      "rss" ->
        {:ok, :rss}

      "feed" ->
        {:ok, :atom}

      "RDF" ->
        if(rss_1_0?(root, attributes), do: {:ok, :rdf}, else: {:error, "unsupported feed format"})

      _ ->
        {:error, "unsupported feed format"}
    end
  end

  defp entries(root, :rss, endpoint_url) do
    channel = first_child(root, "channel") || root
    channel_base = element_base(channel, element_base(root, endpoint_url))

    base_url =
      if local_attribute(root, "base") || local_attribute(channel, "base"),
        do: channel_base,
        else:
          Normalizer.resolve_url(text(first_child(channel, "link")), channel_base) || channel_base

    channel
    |> children("item")
    |> Enum.map(&rss_entry(&1, element_base(&1, base_url)))
  end

  defp entries(root, :atom, endpoint_url) do
    root_base = element_base(root, endpoint_url)

    base_url =
      if local_attribute(root, "base"),
        do: root_base,
        else: Normalizer.resolve_url(atom_link(root), root_base) || root_base

    Enum.map(children(root, "entry"), &atom_entry(&1, element_base(&1, base_url)))
  end

  defp entries(root, :rdf, endpoint_url) do
    root_base_url = element_base(root, endpoint_url)
    channel = first_child(root, "channel")
    channel_base_url = element_base(channel, root_base_url)

    base_url =
      Normalizer.resolve_url(text(first_child(channel, "link")), channel_base_url) ||
        channel_base_url

    item_base_url =
      if local_attribute(root, "base"), do: root_base_url, else: base_url

    root
    |> children("item")
    |> Enum.map(&rdf_entry(&1, element_base(&1, item_base_url)))
  end

  defp rss_entry(item, base_url) do
    %{
      source_entry_id: text(first_child(item, "guid")),
      canonical_url: Normalizer.resolve_url(text(first_child(item, "link")), base_url),
      title: Normalizer.text(text(first_child(item, "title"))),
      content:
        item
        |> first_present(["encoded", "content", "description"])
        |> text()
        |> Normalizer.text(),
      author: Normalizer.text(text(first_present(item, ["creator", "author"]))),
      published_at: Normalizer.date(text(first_present(item, ["pubDate", "date"])))
    }
    |> with_references(item, base_url)
  end

  defp atom_entry(entry, base_url) do
    author = entry |> first_child("author") |> first_child("name") |> text()

    %{
      source_entry_id: text(first_child(entry, "id")),
      canonical_url: Normalizer.resolve_url(atom_link(entry), base_url),
      title: Normalizer.text(text(first_child(entry, "title"))),
      content:
        entry
        |> first_present(["content", "summary"])
        |> text()
        |> Normalizer.text(),
      author: Normalizer.text(author),
      published_at: Normalizer.date(text(first_present(entry, ["published", "updated"])))
    }
    |> with_references(entry, base_url)
  end

  defp rdf_entry(item, base_url) do
    source_entry_id = Normalizer.resolve_url(local_attribute(item, "about"), base_url)
    canonical_url = Normalizer.resolve_url(text(first_child(item, "link")), base_url)

    %{
      source_entry_id: source_entry_id,
      canonical_url: canonical_url || Normalizer.resolve_url(source_entry_id, base_url),
      title: Normalizer.text(text(first_child(item, "title"))),
      content:
        item
        |> first_present(["encoded", "content", "description"])
        |> text()
        |> Normalizer.text(),
      author: Normalizer.text(text(first_present(item, ["creator", "author"]))),
      published_at: Normalizer.date(text(first_present(item, ["date", "pubDate"])))
    }
    |> with_references(item, base_url)
  end

  defp with_references(entry, element, base_url) do
    body = first_present(element, ["encoded", "content", "description", "summary"])
    raw = raw_content(body)

    links =
      case Floki.parse_fragment(raw || "") do
        {:ok, html} -> html |> Floki.find("a[href]") |> Floki.attribute("href")
        _ -> []
      end

    attachments =
      Enum.flat_map(children(element, "enclosure") ++ children(element, "link"), fn {tag, attrs,
                                                                                     _} = link ->
        if local_name(tag) == "enclosure" or attribute(attrs, "rel") == "enclosure" do
          url =
            Normalizer.reference_url(
              attribute(attrs, "url") || attribute(attrs, "href"),
              element_base(link, base_url)
            )

          if url, do: [%{url: url, type: attribute(attrs, "type")}], else: []
        else
          []
        end
      end)

    Map.merge(entry, %{
      entry_url:
        Normalizer.reference_url(
          atom_link(element) || text(first_child(element, "link")),
          base_url
        ),
      updated_at: Normalizer.date(text(first_child(element, "updated"))),
      raw_content: raw,
      attachments: Enum.uniq(attachments),
      body_links:
        links
        |> Enum.map(&Normalizer.reference_url(&1, element_base(body, base_url)))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      feed_fingerprint:
        :crypto.hash(:sha256, :erlang.term_to_binary(element)) |> Base.encode16(case: :lower)
    })
  end

  defp raw_content(nil), do: nil

  defp raw_content({_, _, content}) do
    if Enum.all?(content, &is_binary/1), do: Enum.join(content), else: Floki.raw_html(content)
  end

  defp atom_link(element) do
    element
    |> children("link")
    |> Enum.find(fn {_, attributes, _} ->
      attribute(attributes, "rel", "alternate") in ["alternate", ""]
    end)
    |> case do
      nil -> nil
      {_, attributes, content} -> attribute(attributes, "href") || text({"text", [], content})
    end
  end

  defp first_present(element, names) do
    Enum.find_value(names, &first_child(element, &1))
  end

  defp first_child(nil, _name), do: nil
  defp first_child(element, name), do: Enum.find(children(element, name), fn _ -> true end)

  defp children({_, _, content}, name) do
    Enum.filter(content, fn
      {tag, _, _} -> local_name(tag) == name
      _ -> false
    end)
  end

  defp text(nil), do: nil
  defp text({_, _, content}), do: content |> collect_text() |> IO.iodata_to_binary()

  defp collect_text(content) do
    Enum.map(content, fn
      value when is_binary(value) -> value
      {_, _, nested} -> collect_text(nested)
    end)
  end

  defp local_name(name), do: name |> String.split(":") |> List.last()

  defp rss_1_0?(root, attributes) do
    Enum.any?(attributes, fn {_, value} -> value == @rss_1_0_namespace end) and
      first_child(root, "channel") != nil
  end

  defp element_base(nil, fallback), do: fallback

  defp element_base({_, attributes, _}, fallback) do
    case local_attribute(attributes, "base") do
      nil -> fallback
      value -> Normalizer.resolve_url(value, fallback) || fallback
    end
  end

  defp attribute(attributes, name, default \\ nil),
    do: attributes |> List.keyfind(name, 0, {nil, default}) |> elem(1)

  defp local_attribute({_, attributes, _}, name), do: local_attribute(attributes, name)

  defp local_attribute(attributes, name) do
    Enum.find_value(attributes, fn {attribute_name, value} ->
      if local_name(attribute_name) == name, do: value
    end)
  end

  defp message(error) when is_binary(error), do: error
  defp message(error), do: Exception.message(error)
end
