defmodule Lens.Ingestion.Normalizer do
  @block_tags ~r/<\/?(?:address|article|blockquote|br|div|h[1-6]|li|p|pre|section|tr)[^>]*>/i
  @tags ~r/<[^>]*>/

  @spec text(String.t() | nil) :: String.t() | nil
  def text(nil), do: nil

  def text(value) when is_binary(value) do
    value
    |> String.replace(~r/<(?:script|style)\b[^>]*>.*?<\/(?:script|style)>/is, "")
    |> String.replace(@block_tags, "\n\n")
    |> String.replace(@tags, "")
    |> decode_entities()
    |> String.replace("\r\n", "\n")
    |> String.split("\n", trim: false)
    |> Enum.map(&String.trim/1)
    |> Enum.join("\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
    |> blank_to_nil()
  end

  @spec resolve_url(String.t() | nil, String.t()) :: String.t() | nil
  def resolve_url(nil, _base_url), do: nil

  def resolve_url(value, base_url) when is_binary(value) and is_binary(base_url) do
    base_url
    |> URI.merge(String.trim(value))
    |> URI.to_string()
    |> Lens.Content.Identity.normalize_url()
  rescue
    ArgumentError -> nil
  end

  @spec date(String.t() | nil) :: DateTime.t() | nil
  def date(nil), do: nil

  def date(value) when is_binary(value) do
    value = String.trim(value)

    case DateTime.from_iso8601(value) do
      {:ok, date, _offset} -> date
      _ -> parse_http_date(value)
    end
  end

  defp parse_http_date(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{year, month, day}, {hour, minute, second}} ->
        {:ok, datetime} =
          DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, second), "Etc/UTC")

        datetime

      :bad_date ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  defp decode_entities(value) do
    value
    |> String.replace("&nbsp;", " ")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> then(fn text ->
      Regex.replace(~r/&#(x[0-9a-fA-F]+|\d+);/, text, fn _, codepoint ->
        codepoint =
          if String.starts_with?(codepoint, "x"),
            do: String.to_integer(String.slice(codepoint, 1..-1//1), 16),
            else: String.to_integer(codepoint)

        <<codepoint::utf8>>
      end)
    end)
  rescue
    ArgumentError -> value
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
