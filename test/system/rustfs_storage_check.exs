Application.ensure_all_started(:req)
ExUnit.start(seed: 0)

defmodule Lens.RustFSStorageCheck do
  use ExUnit.Case, async: false
  alias Lens.Earnings.RustFS

  setup_all do
    endpoint = System.fetch_env!("LENS_RUSTFS_ENDPOINT")
    bucket = "lens-storage-check-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    {:ok, client} =
      RustFS.new(
        endpoint: endpoint,
        bucket: bucket,
        access_key_id: System.fetch_env!("LENS_RUSTFS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("LENS_RUSTFS_SECRET_ACCESS_KEY"),
        region: System.get_env("LENS_RUSTFS_REGION", "us-east-1")
      )

    assert {:ok, %{status: 200}} = Req.put(client.request, url: endpoint <> "/" <> bucket)
    %{client: client}
  end

  test "exact bytes, identical reuse and changed originals", %{client: client} do
    bytes = <<"%PDF-1.7\nroundtrip", 0, 255, 13, 10>>
    assert {:ok, original} = RustFS.put(client, bytes)
    assert RustFS.get(client, original) == {:ok, bytes}
    assert RustFS.put(client, bytes) == {:ok, original}
    assert {:ok, changed} = RustFS.put(client, bytes <> "changed")
    assert changed.key != original.key
    assert RustFS.get(client, original) == {:ok, bytes}
  end

  test "simultaneous conditional creates never overwrite the winner", %{client: client} do
    for round <- 1..3 do
      seed = "%PDF-concurrent-round-#{round}"
      key = reference(seed).key
      url = client.endpoint <> "/" <> client.bucket <> "/" <> key
      owner = self()
      gate = make_ref()

      tasks =
        for index <- 1..8 do
          Task.async(fn ->
            send(owner, {gate, :ready, self()})

            receive do
              {^gate, :go} -> :ok
            after
              5_000 -> flunk("concurrent create gate timed out")
            end

            bytes = seed <> "-writer-#{index}"

            assert {:ok, response} =
                     Req.put(client.request,
                       url: url,
                       headers: [{"if-none-match", "*"}],
                       body: bytes
                     )

            {response.status, bytes}
          end)
        end

      for _ <- tasks do
        assert_receive {^gate, :ready, _}, 5_000
      end

      Enum.each(tasks, &send(&1.pid, {gate, :go}))
      results = Enum.map(tasks, &Task.await(&1, 30_000))
      assert [{200, winner}] = Enum.filter(results, fn {status, _} -> status == 200 end)
      assert Enum.all?(results, fn {status, _} -> status in [200, 412, 409] end)
      assert {:ok, %{status: 200, body: ^winner}} = Req.get(client.request, url: url)

      assert {:ok, %{status: 412}} =
               Req.put(client.request, url: url, headers: [{"if-none-match", "*"}], body: "other")

      assert {:ok, %{status: 200, body: ^winner}} = Req.get(client.request, url: url)
    end
  end

  test "concurrent identical client writes reuse one verified original", %{client: client} do
    bytes = "%PDF-client-concurrency"

    results =
      1..8
      |> Task.async_stream(fn _ -> RustFS.put(client, bytes) end, max_concurrency: 8)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.any?(results, &match?({:ok, _}, &1))
    assert Enum.all?(results, &(&1 in [{:ok, reference(bytes)}, {:error, :conflict}]))
    assert RustFS.put(client, bytes) == {:ok, reference(bytes)}
    assert RustFS.get(client, reference(bytes)) == {:ok, bytes}
  end

  test "missing and corrupt objects are explicit and corruption is never overwritten", %{
    client: client
  } do
    assert RustFS.get(client, reference("%PDF-missing")) == {:error, :not_found}
    bytes = "%PDF-expected"
    reference = reference(bytes)
    url = client.endpoint <> "/" <> client.bucket <> "/" <> reference.key
    corrupt = :binary.copy("x", byte_size(bytes))
    assert {:ok, %{status: 200}} = Req.put(client.request, url: url, body: corrupt)
    assert RustFS.get(client, reference) == {:error, :integrity_error}
    assert RustFS.put(client, bytes) == {:error, :integrity_error}
    assert {:ok, %{status: 200, body: ^corrupt}} = Req.get(client.request, url: url)
  end

  test "20 MiB boundary is enforced against the server", %{client: client} do
    bytes = :binary.copy("x", 20_971_520)
    assert {:ok, reference} = RustFS.put(client, bytes)
    assert RustFS.get(client, reference) == {:ok, bytes}
    assert RustFS.put(client, bytes <> "x") == {:error, :too_large}
  end

  defp reference(bytes) do
    hash = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    %{
      sha256: hash,
      byte_size: byte_size(bytes),
      key: "earnings/originals/sha256/" <> hash <> ".pdf"
    }
  end
end
