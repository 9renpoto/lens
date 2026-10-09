defmodule Lens.Earnings.RustFS do
  @moduledoc """
  Create-only RustFS storage and verified retrieval of retained PDF bytes.

  This low-level client does not record acquisitions or run recovery. Callers must
  durably prepare work before writing (ADR 0006). Collection remains PostgreSQL-backed
  until that protocol is implemented.
  """

  @limit 20_971_520
  @prefix "earnings/originals/sha256/"
  @derive {Inspect, only: [:endpoint, :bucket, :timeout_ms]}
  @enforce_keys [:endpoint, :bucket, :timeout_ms, :request]
  defstruct [:endpoint, :bucket, :timeout_ms, :request]

  @type object_reference :: %{key: String.t(), sha256: String.t(), byte_size: pos_integer()}
  @type t :: %__MODULE__{}

  @doc "Build a client for one endpoint/bucket; credentials are excluded from inspection."
  def new(options \\ Application.get_env(:lens, __MODULE__, []))
  def new([]), do: {:error, :not_configured}

  def new(options) when is_list(options) do
    if valid_options?(options) do
      endpoint = String.trim_trailing(options[:endpoint], "/")
      timeout = Keyword.get(options, :timeout_ms, 30_000)

      request =
        Req.new(
          aws_sigv4: [
            service: "s3",
            region: Keyword.get(options, :region, "us-east-1"),
            access_key_id: options[:access_key_id],
            secret_access_key: options[:secret_access_key]
          ],
          headers: [{"accept-encoding", "identity"}],
          compressed: false,
          raw: true,
          redirect: false,
          retry: false,
          receive_timeout: timeout,
          finch: [pool_timeout: timeout, conn_opts: [transport_opts: [timeout: timeout]]]
        )

      {:ok,
       %__MODULE__{
         endpoint: endpoint,
         bucket: options[:bucket],
         timeout_ms: timeout,
         request: request
       }}
    else
      {:error, :invalid_configuration}
    end
  end

  def new(_), do: {:error, :invalid_configuration}

  @doc "Create at a content-derived key without overwriting; verify by reading before returning."
  @spec put(t(), binary()) :: {:ok, object_reference()} | {:error, atom() | tuple()}
  def put(%__MODULE__{} = client, bytes) when is_binary(bytes) and byte_size(bytes) > 0 do
    if byte_size(bytes) > @limit do
      {:error, :too_large}
    else
      reference = reference(bytes)

      with {:ok, response} <-
             request(client, reference, :put,
               body: bytes,
               headers: [{"if-none-match", "*"}, {"content-type", "application/pdf"}]
             ),
           :ok <- write_status(response.status),
           {:ok, _verified_bytes} <- get(client, reference) do
        {:ok, reference}
      end
    end
  end

  def put(%__MODULE__{}, _), do: {:error, :invalid_bytes}

  @doc "Fetch raw bytes only when key, size and SHA-256 match the retained reference."
  @spec get(t(), object_reference()) :: {:ok, binary()} | {:error, atom() | tuple()}
  def get(%__MODULE__{} = client, reference) do
    if valid_reference?(reference) do
      with {:ok, response} <- request(client, reference, :get, []),
           :ok <- read_status(response.status),
           :ok <- stream_status(response),
           bytes <- response_bytes(response),
           true <- byte_size(bytes) == reference.byte_size and hash(bytes) == reference.sha256 do
        {:ok, bytes}
      else
        false -> {:error, :integrity_error}
        {:error, _} = error -> error
      end
    else
      {:error, :invalid_reference}
    end
  end

  defp request(client, reference, method, options) do
    task =
      Task.async(fn ->
        try do
          Req.request(
            client.request,
            [
              method: method,
              url: client.endpoint <> "/" <> client.bucket <> "/" <> reference.key,
              into: &collect(&1, &2, reference.byte_size)
            ] ++ options
          )
        rescue
          _ -> {:error, :transport_error}
        end
      end)

    case Task.yield(task, client.timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, response}} -> {:ok, response}
      {:ok, {:error, _}} -> {:error, :transport_error}
      nil -> {:error, :timeout}
    end
  end

  defp collect({:data, data}, {request, response}, limit) do
    if request.method == :get and response.status == 200 do
      size = Map.get(response.private, :lens_size, 0) + byte_size(data)

      if size > limit or not identity_encoding?(response) do
        {:halt, {request, put_in(response.private[:lens_integrity_error], true)}}
      else
        response =
          response
          |> put_in([Access.key(:private), :lens_size], size)
          |> put_in(
            [Access.key(:private), :lens_chunks],
            [data | Map.get(response.private, :lens_chunks, [])]
          )

        {:cont, {request, response}}
      end
    else
      {:cont, {request, response}}
    end
  end

  defp stream_status(response) do
    if response.private[:lens_integrity_error] == true or not identity_encoding?(response),
      do: {:error, :integrity_error},
      else: :ok
  end

  defp identity_encoding?(response),
    do: Req.Response.get_header(response, "content-encoding") in [[], ["identity"]]

  defp response_bytes(response) do
    response.private
    |> Map.get(:lens_chunks, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp write_status(status) when status in [200, 201, 204, 412], do: :ok
  defp write_status(status), do: error_status(status)
  defp read_status(200), do: :ok
  defp read_status(status), do: error_status(status)

  defp error_status(404), do: {:error, :not_found}
  defp error_status(status) when status in [401, 403], do: {:error, :unauthorized}
  defp error_status(409), do: {:error, :conflict}
  defp error_status(status) when status == 429 or status >= 500, do: {:error, :unavailable}
  defp error_status(status), do: {:error, {:http_error, status}}

  defp reference(bytes) do
    sha256 = hash(bytes)
    %{key: @prefix <> sha256 <> ".pdf", sha256: sha256, byte_size: byte_size(bytes)}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp valid_reference?(%{key: key, sha256: sha256, byte_size: size})
       when is_binary(sha256) and is_integer(size) and size in 1..@limit do
    Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256) and key == @prefix <> sha256 <> ".pdf"
  end

  defp valid_reference?(_), do: false

  defp valid_options?(options) do
    Keyword.keyword?(options) and valid_endpoint?(options[:endpoint]) and
      valid_bucket?(options[:bucket]) and nonempty?(options[:access_key_id]) and
      nonempty?(options[:secret_access_key]) and
      nonempty?(Keyword.get(options, :region, "us-east-1")) and
      valid_timeout?(Keyword.get(options, :timeout_ms, 30_000))
  end

  defp valid_endpoint?(endpoint) when is_binary(endpoint) do
    case URI.new(endpoint) do
      {:ok, uri} ->
        uri.scheme in ["http", "https"] and nonempty?(uri.host) and
          is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
          uri.path in [nil, "", "/"] and is_integer(uri.port) and uri.port in 1..65_535

      {:error, _} ->
        false
    end
  end

  defp valid_endpoint?(_), do: false

  defp valid_bucket?(bucket) when is_binary(bucket),
    do: Regex.match?(~r/\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z/, bucket)

  defp valid_bucket?(_), do: false
  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout in 1..30_000
  defp nonempty?(value), do: is_binary(value) and byte_size(value) > 0
end
