defmodule Lens.Search.Normalizer do
  @moduledoc false

  @spec document_text(String.t() | nil, String.t() | nil) :: String.t()
  def document_text(title, content), do: join(title, content)

  @spec title_text(String.t() | nil) :: String.t()
  def title_text(title), do: normalize(title)

  @spec normalize_query(String.t()) :: {:ok, String.t()} | :error
  def normalize_query(query) when is_binary(query) do
    normalized = normalize(query)

    if length(String.graphemes(normalized)) >= 2 and Regex.match?(~r/[\p{L}\p{N}]/u, normalized) do
      {:ok, escape_like(normalized)}
    else
      :error
    end
  end

  defp join(title, content) do
    [title, content]
    |> Enum.map(&normalize/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp normalize(value) when is_binary(value),
    do: value |> String.normalize(:nfkc) |> String.downcase()

  defp normalize(_), do: ""

  defp escape_like(query) do
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
