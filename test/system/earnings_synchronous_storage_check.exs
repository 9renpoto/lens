# Run with an isolated disposable PostgreSQL database and RustFS bucket namespace.
Application.ensure_all_started(:ecto_sql)
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:req)
config = Application.fetch_env!(:lens, Lens.Repo)
Application.put_env(:lens, Lens.Repo, Keyword.put(config, :pool, DBConnection.ConnectionPool))
{:ok, repo} = Lens.Repo.start_link()
Process.unlink(repo)
Lens.Release.prepare()
ExUnit.start(seed: 0)

defmodule Lens.SynchronousStorageCheck do
  use ExUnit.Case, async: false
  alias Lens.Earnings.{Acquisition, HTTPCheck, HTTPHistory, Original, RustFS}
  alias Lens.Repo

  setup_all do
    bucket = "lens-save-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    {:ok, client} =
      RustFS.new(
        endpoint: System.fetch_env!("LENS_RUSTFS_ENDPOINT"),
        bucket: bucket,
        access_key_id: System.fetch_env!("LENS_RUSTFS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("LENS_RUSTFS_SECRET_ACCESS_KEY")
      )

    assert {:ok, %{status: 200}} = Req.put(client.request, url: client.endpoint <> "/" <> bucket)
    %{client: client}
  end

  setup do
    id = Ecto.UUID.generate()

    attrs = %{
      check_id: id,
      issuer_code: "issuer-alpha",
      kind: :pdf,
      url: "https://publisher.invalid/" <> id,
      checked_at: DateTime.utc_now(),
      metadata: %{},
      result: %{
        outcome: :success,
        final_url: "https://publisher.invalid/" <> id,
        bytes: "%PDF-" <> id,
        http_status: 200,
        requests: 1,
        retryable: false,
        headers: %{}
      }
    }

    %{attrs: attrs, bytes: attrs.result.bytes}
  end

  test "bounded collection stores verified originals and repeated runs preserve history", c do
    alias Lens.Earnings.{Collector, HTTPCheck, Original, Sources}

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    worker = spawn(fn -> serve_collection(listener, c.bytes) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(worker, :kill)
    end)

    {:ok, target} =
      Lens.Analysis.create_target(%{
        security_code: "000159-" <> Ecto.UUID.generate(),
        market: "TSE",
        display_name: "Real collection",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: "http://127.0.0.1:#{port}/results"})
    # The first sorted source consumes the bounded run; no publisher.invalid fixture is fetched.
    assert {:ok, first} = Collector.run(rustfs: c.client, max_operations: 2)
    assert first.budget.operations == 2
    assert [%{kind: "pdf"} = check] = Enum.filter(first.checks, &(&1.kind == "pdf"))
    assert check.metadata["source_id"] == source.id
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    assert acquisition.release_id == nil
    assert Repo.get!(Original, acquisition.original_id).endpoint == c.client.endpoint

    assert Lens.Earnings.original_bytes(acquisition.original_id, rustfs: c.client) ==
             {:ok, c.bytes}

    assert {:ok, second} = Collector.run(rustfs: c.client, max_operations: 2)
    assert [%{kind: "pdf"} = next] = Enum.filter(second.checks, &(&1.kind == "pdf"))
    assert next.id != check.id
    assert next.acquisition_id != check.acquisition_id
    assert Repo.get!(Acquisition, next.acquisition_id).original_id == acquisition.original_id
    {:ok, _} = Sources.update(source, %{enabled: false})
    assert Repo.get!(HTTPCheck, check.id) == check
    assert Repo.get!(Acquisition, acquisition.id) == acquisition
  end

  defp serve_collection(listener, bytes) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, request} = :gen_tcp.recv(socket, 0, 2000)

        body =
          if String.starts_with?(request, "GET /report.pdf "),
            do: bytes,
            else: ~s(<a href="/report.pdf">Results</a>)

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n",
          body
        ])

        :gen_tcp.close(socket)
        serve_collection(listener, bytes)

      _ ->
        :ok
    end
  end

  test "failed save is explicit and a new observation can save without a recovery queue", c do
    bad = %{
      c.client
      | bucket: "absent-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    }

    assert {:storage_failed, "not_found"} = HTTPHistory.store(c.attrs, bad)
    failed = Repo.get_by!(Acquisition, acquisition_id: "http:" <> c.attrs.check_id)
    assert failed.status == "failed"
    assert failed.original_id == nil
    assert Repo.get_by(HTTPCheck, check_id: c.attrs.check_id) == nil
    next = %{c.attrs | check_id: Ecto.UUID.generate()}
    assert {:ok, check} = HTTPHistory.store(next, c.client)
    successful = Repo.get!(Acquisition, check.acquisition_id)

    assert Lens.Earnings.original_bytes(successful.original_id, rustfs: c.client) ==
             {:ok, c.bytes}
  end

  test "an already written object is verified and reused without recovery state", c do
    assert {:ok, reference} = RustFS.put(c.client, c.bytes)
    assert {:ok, check} = HTTPHistory.store(c.attrs, c.client)
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    assert Repo.get!(Original, acquisition.original_id).sha256 == reference.sha256

    assert Lens.Earnings.original_bytes(acquisition.original_id, rustfs: c.client) ==
             {:ok, c.bytes}
  end
end
