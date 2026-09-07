defmodule Lens.Ingestion.Fetcher do
  alias Lens.Content.Source

  @default_timeout 10_000
  @default_max_bytes 5_000_000
  @default_max_redirects 3

  def fetch(%Source{} = source, options \\ []) do
    request = %{
      url: source.endpoint_url,
      headers: conditional_headers(source),
      timeout: Keyword.get(options, :timeout, @default_timeout),
      max_bytes: Keyword.get(options, :max_bytes, @default_max_bytes),
      max_redirects: Keyword.get(options, :max_redirects, @default_max_redirects)
    }

    response =
      case Keyword.get(options, :transport) do
        transport when is_function(transport, 1) -> transport.(request)
        nil -> request_with_req(request)
      end

    normalize_response(response, request.max_bytes)
  end

  defp request_with_req(request) do
    case Req.get(request.url,
           headers: request.headers,
           receive_timeout: request.timeout,
           connect_options: [timeout: request.timeout],
           max_redirects: request.max_redirects,
           retry: false,
           decode_body: false
         ) do
      {:ok, response} ->
        {:ok, %{status: response.status, headers: response.headers, body: response.body}}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp normalize_response({:ok, %{status: 304, headers: headers}}, _max_bytes),
    do: {:not_modified, normalize_headers(headers)}

  defp normalize_response({:ok, %{status: status, headers: headers, body: body}}, max_bytes)
       when status in 200..299 and is_binary(body) do
    headers = normalize_headers(headers)

    cond do
      content_length_exceeds_limit?(headers, max_bytes) -> {:error, "response exceeds byte limit"}
      byte_size(body) > max_bytes -> {:error, "response exceeds byte limit"}
      true -> {:ok, %{status: status, headers: headers, body: body}}
    end
  end

  defp normalize_response({:ok, %{status: status}}, _max_bytes),
    do: {:error, "unexpected HTTP status #{status}"}

  defp normalize_response({:error, error}, _max_bytes), do: {:error, to_string(error)}

  defp normalize_response(other, _max_bytes),
    do: {:error, "invalid transport response: #{inspect(other)}"}

  defp conditional_headers(source) do
    []
    |> maybe_put_header("if-none-match", source.etag)
    |> maybe_put_header("if-modified-since", source.last_modified)
  end

  defp maybe_put_header(headers, _name, nil), do: headers
  defp maybe_put_header(headers, name, value), do: [{name, value} | headers]

  defp normalize_headers(headers) when is_map(headers),
    do: Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(to_string(key)), value} end)
  end

  defp content_length_exceeds_limit?(headers, max_bytes) do
    case Integer.parse(to_string(Map.get(headers, "content-length", ""))) do
      {content_length, ""} -> content_length > max_bytes
      _ -> false
    end
  end
end
