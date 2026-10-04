defmodule Lens.Earnings.HTTPResponseFacts do
  @moduledoc "Pure interpretation of response facts shared by acquisition and persistence."

  def size_cap(kind) when kind in [:listing, "listing"], do: 2_097_152
  def size_cap(_kind), do: 20_971_520

  def header_bytes(headers, name, default \\ nil)

  def header_bytes(headers, name, default) when is_map(headers) do
    with {:ok, json} <- headers |> normalize_headers() |> Jason.encode(),
         {:ok, %{} = canonical} <- Jason.decode(json) do
      decode_header(Map.get(canonical, name, default))
    else
      _ -> :error
    end
  end

  def header_bytes(_headers, _name, _default), do: :error

  def normalize_headers(headers) when is_map(headers) and not is_struct(headers) do
    Map.new(headers, fn {name, value} ->
      normalized =
        if is_binary(value) and not String.valid?(value) and
             :binary.match(value, <<0>>) == :nomatch,
           do: %{"encoding" => "base64", "value" => Base.encode64(value)},
           else: value

      {name, normalized}
    end)
  end

  def normalize_headers(headers), do: headers

  def advertised_size(headers) do
    with {:ok, value} <- header_bytes(headers, "content-length"),
         {size, ""} <- Integer.parse(value) do
      {:ok, size}
    else
      _ -> :error
    end
  end

  def oversized?(headers, limit) do
    case advertised_size(headers) do
      {:ok, size} -> size > limit
      _ -> false
    end
  end

  def identity_encoding?(headers) do
    with {:ok, encoding} <- header_bytes(headers, "content-encoding", "identity"),
         true <- String.valid?(encoding) do
      encoding
      |> String.split(",")
      |> Enum.all?(&(String.downcase(String.trim(&1)) == "identity"))
    else
      _ -> false
    end
  end

  def redirect_target(final_url, headers) do
    with {:ok, location} <- header_bytes(headers, "location"),
         {:ok, reference} <- URI.new(location) do
      {:ok, final_url |> URI.merge(reference) |> URI.to_string()}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp decode_header(value) when is_binary(value), do: {:ok, value}

  defp decode_header(value) do
    with {:ok, json} <- Jason.encode(value),
         {:ok, canonical} <- Jason.decode(json) do
      case canonical do
        value when is_binary(value) -> {:ok, value}
        %{"encoding" => "base64", "value" => value} when is_binary(value) -> Base.decode64(value)
        _ -> :error
      end
    else
      _ -> :error
    end
  end
end
