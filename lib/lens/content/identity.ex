defmodule Lens.Content.Identity do
  @moduledoc false

  def normalize_entry(source_id, attrs) do
    canonical_url = normalize_url(fetch(attrs, :canonical_url))
    title = fetch(attrs, :title)
    content = fetch(attrs, :content)
    published_at = fetch(attrs, :published_at)

    %{
      identity_key:
        identity_key(
          source_id,
          canonical_url,
          fetch(attrs, :source_entry_id),
          title,
          published_at,
          content
        ),
      canonical_url: canonical_url,
      title: title,
      content: content,
      author: fetch(attrs, :author),
      published_at: published_at,
      metadata: fetch(attrs, :metadata) || %{},
      content_hash: content_hash(title, content)
    }
  end

  def normalize_url(value) when is_binary(value) do
    uri = URI.parse(value)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.userinfo == nil do
      scheme = String.downcase(uri.scheme)
      host = String.downcase(uri.host)

      port =
        if (scheme == "http" and uri.port == 80) or (scheme == "https" and uri.port == 443),
          do: nil,
          else: uri.port

      URI.to_string(%URI{uri | scheme: scheme, host: host, port: port, fragment: nil})
    end
  end

  def normalize_url(_), do: nil

  def content_hash(title, content) do
    hash([value(title), "\n", value(content)])
  end

  defp identity_key(_source_id, canonical_url, _entry_id, _title, _published_at, _content)
       when is_binary(canonical_url),
       do: "url:" <> canonical_url

  defp identity_key(source_id, nil, entry_id, _title, _published_at, _content)
       when is_binary(entry_id) and byte_size(entry_id) > 0,
       do: "entry:" <> source_id <> ":" <> entry_id

  defp identity_key(source_id, nil, _entry_id, title, published_at, content) do
    published_value = published_at_value(published_at)

    "fallback:" <>
      source_id <> ":" <> hash([value(title), "\n", published_value, "\n", value(content)])
  end

  defp published_at_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp published_at_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp published_at_value(value), do: value(value)

  defp fetch(attrs, key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp value(nil), do: ""
  defp value(value) when is_binary(value), do: value
  defp value(value), do: to_string(value)

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
