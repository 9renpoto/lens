defmodule Lens.StorageFixtures do
  @moduledoc false
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    :ets.new(__MODULE__, [:named_table, :public, :set])
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    spawn_link(fn -> serve(listener) end)
    {:ok, "http://127.0.0.1:#{port}"}
  end

  def handle_call(:endpoint, _, endpoint), do: {:reply, endpoint, endpoint}

  def options do
    [
      endpoint: GenServer.call(__MODULE__, :endpoint),
      bucket: "fixture-originals",
      access_key_id: "fixture",
      secret_access_key: "fixture"
    ]
  end

  def reference(bytes) do
    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    key = "earnings/originals/sha256/#{digest}.pdf"
    :ets.insert(__MODULE__, {key, bytes})

    %{
      endpoint: options()[:endpoint],
      bucket: "fixture-originals",
      key: key,
      sha256: digest,
      byte_size: byte_size(bytes)
    }
  end

  def record_success(%{bytes: bytes} = attrs) when is_binary(bytes) do
    Lens.Earnings.record_success(Map.put_new(attrs, :storage_reference, reference(bytes)))
  end

  def record_success(attrs), do: Lens.Earnings.record_success(attrs)

  def record_http(%{result: %{outcome: :success, bytes: bytes}} = attrs) when is_binary(bytes) do
    if Map.get(attrs, :kind, :pdf) in [:pdf, "pdf"] do
      Lens.Earnings.HTTPHistory.record(Map.put_new(attrs, :storage_reference, reference(bytes)))
    else
      Lens.Earnings.HTTPHistory.record(attrs)
    end
  end

  def record_http(attrs), do: Lens.Earnings.HTTPHistory.record(attrs)

  defp serve(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        case :gen_tcp.recv(socket, 0, 2000) do
          {:ok, request} ->
            [_, path | _] = String.split(request, " ")
            key = String.replace_prefix(path, "/fixture-originals/", "")

            {status, body} =
              case :ets.lookup(__MODULE__, key) do
                [{_, bytes}] -> {200, bytes}
                [] -> {404, ""}
              end

            :gen_tcp.send(socket, [
              "HTTP/1.1 #{status} Response\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n",
              body
            ])

          _ ->
            :ok
        end

        :gen_tcp.close(socket)
        serve(listener)

      _ ->
        :ok
    end
  end
end
