# Run with a disposable PostgreSQL database and RustFS bucket namespace.
Application.ensure_all_started(:ecto_sql)
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:req)
config = Application.fetch_env!(:lens, Lens.Repo)
Application.put_env(:lens, Lens.Repo, Keyword.put(config, :pool, DBConnection.ConnectionPool))
{:ok, repo} = Lens.Repo.start_link()
Process.unlink(repo)
Ecto.Migrator.run(Lens.Repo, Application.app_dir(:lens, "priv/repo/migrations"), :up, all: true)
ExUnit.start(seed: 0)

defmodule Lens.StorageRecoveryCheck do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Lens.Earnings.{Acquisition, RustFS, StorageWork}
  alias Lens.Repo

  setup_all do
    bucket = "lens-recovery-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

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
      acquisition_id: id,
      issuer_code: "1234",
      url: "https://publisher.invalid/" <> id,
      acquired_at: DateTime.utc_now(),
      bytes: "%PDF-" <> id
    }

    %{attrs: attrs}
  end

  test "bounded collection stores verified originals and repeated runs preserve history", c do
    alias Lens.Earnings.{Collector, HTTPCheck, Original, Sources}

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    worker = spawn(fn -> serve_collection(listener, c.attrs.bytes) end)

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
    assert Repo.get!(Original, acquisition.original_id).bytes == nil

    assert Lens.Earnings.original_bytes(acquisition.original_id, rustfs: c.client) ==
             {:ok, c.attrs.bytes}

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

  test "collected HTTP provenance survives worker death and completion rollback", c do
    alias Lens.Earnings.{HTTPCheck, HTTPHistory, Sources}

    {:ok, target} =
      Lens.Analysis.create_target(%{
        security_code: "C159-" <> Ecto.UUID.generate(),
        market: "TSE",
        display_name: "Collection recovery",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: "https://publisher.invalid/results"})
    check_id = Ecto.UUID.generate()

    attrs = %{
      check_id: check_id,
      issuer_code: target.security_code,
      kind: :pdf,
      url: "https://publisher.invalid/request.pdf",
      checked_at: DateTime.utc_now(),
      metadata: %{source_id: source.id, anchor_text: "Results"},
      result: %{
        outcome: :success,
        final_url: "https://publisher.invalid/actual.pdf",
        bytes: c.attrs.bytes,
        http_status: 200,
        requests: 1,
        retryable: false,
        headers: %{}
      }
    }

    owner = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        assert {:ok, work} = HTTPHistory.prepare_storage(attrs, c.client)
        send(owner, {:collected, work.id})
        exit(:killed)
      end)

    assert_receive {:collected, id}, 5000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    work = Repo.get!(StorageWork, id)
    assert work.source_id == source.id
    assert work.http_check["metadata"]["anchor_text"] == "Results"
    assert StorageWork.unfinished_for_source?(source.id)
    refute Repo.get_by(HTTPCheck, check_id: check_id)
    refute Repo.get_by(Acquisition, acquisition_id: "http:" <> check_id)

    old = DateTime.add(DateTime.utc_now(), -500, :second)
    {:ok, claim} = StorageWork.claim(id, old)
    assert {:ok, reference} = RustFS.put(c.client, work.bytes)

    assert {:error, :interrupted} =
             Repo.transaction(fn ->
               assert {:ok, %{status: "completed"}} =
                        StorageWork.finish(claim, {:ok, work.bytes, reference}, old)

               assert Repo.get_by!(HTTPCheck, check_id: check_id).metadata["source_id"] ==
                        source.id

               Repo.rollback(:interrupted)
             end)

    refute Repo.get_by(HTTPCheck, check_id: check_id)
    refute Repo.get_by(Acquisition, acquisition_id: "http:" <> check_id)
    assert Repo.get!(StorageWork, id).bytes == work.bytes
    assert {:error, :not_eligible} = StorageWork.recover(id, c.client)
    assert {:ok, completed} = StorageWork.recover(id, c.client)
    check = Repo.get_by!(HTTPCheck, check_id: check_id)
    assert check.acquisition_id == completed.acquisition_record_id
    assert check.checked_at == attrs.checked_at
    assert check.final_url == attrs.result.final_url
    assert check.metadata["anchor_text"] == "Results"
    refute StorageWork.unfinished_for_source?(source.id)
    assert {:error, :not_eligible} = StorageWork.recover(id, c.client)

    assert Repo.aggregate(
             from(a in Acquisition, where: a.acquisition_id == ^("http:" <> check_id)),
             :count
           ) == 1
  end

  test "concurrent collected preparations keep one source work and one retry budget", c do
    alias Lens.Earnings.{HTTPHistory, Sources}

    {:ok, target} =
      Lens.Analysis.create_target(%{
        security_code: "P159-" <> Ecto.UUID.generate(),
        market: "TSE",
        display_name: "Concurrent collection",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: "https://publisher.invalid/results"})
    now = DateTime.utc_now()

    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          HTTPHistory.prepare_storage(
            %{
              check_id: Ecto.UUID.generate(),
              issuer_code: target.security_code,
              kind: :pdf,
              url: "https://publisher.invalid/report.pdf",
              checked_at: now,
              metadata: %{source_id: source.id},
              result: %{
                outcome: :success,
                final_url: "https://publisher.invalid/report.pdf",
                bytes: c.attrs.bytes,
                http_status: 200,
                requests: 1,
                retryable: false,
                headers: %{}
              }
            },
            c.client
          )
        end,
        max_concurrency: 8
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, work}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &(&1 == {:error, :source_busy})) == 7
    assert work.attempts == 0
    assert Repo.aggregate(from(w in StorageWork, where: w.source_id == ^source.id), :count) == 1
    assert {:ok, %{status: "completed", attempts: 1}} = StorageWork.recover(work.id, c.client)
  end

  test "committed preparation survives worker death before object write", c do
    owner = self()
    old = DateTime.add(DateTime.utc_now(), -500, :second)

    {pid, monitor} =
      spawn_monitor(fn ->
        {:ok, work} = StorageWork.prepare(c.attrs, c.client)
        {:ok, _} = StorageWork.claim(work.id, old)
        send(owner, {:prepared, work.id})
        exit(:killed)
      end)

    assert_receive {:prepared, id}, 5000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    assert Repo.get!(StorageWork, id).bytes == c.attrs.bytes
    assert {:error, :not_eligible} = StorageWork.recover(id, c.client)
    assert {:ok, completed} = StorageWork.recover(id, c.client)
    assert completed.status == "completed"
    assert completed.attempts == 2

    assert RustFS.get(c.client, Map.take(completed, [:key, :sha256, :byte_size])) ==
             {:ok, c.attrs.bytes}
  end

  test "object survives completion rollback and is reused after lease expiry", c do
    old = DateTime.add(DateTime.utc_now(), -500, :second)
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    {:ok, claim} = StorageWork.claim(work.id, old)
    assert {:ok, _} = RustFS.put(c.client, c.attrs.bytes)

    assert {:error, :interrupted} =
             Repo.transaction(fn ->
               assert {:ok, %{status: "completed"}} =
                        StorageWork.finish(claim, {:ok, c.attrs.bytes}, old)

               Repo.rollback(:interrupted)
             end)

    refute Repo.get_by(Acquisition, acquisition_id: c.attrs.acquisition_id)
    assert Repo.get!(StorageWork, work.id).bytes == c.attrs.bytes
    assert {:error, :not_eligible} = StorageWork.recover(work.id, c.client)
    assert {:ok, %{status: "completed"}} = StorageWork.recover(work.id, c.client)
    assert Repo.get_by!(Acquisition, acquisition_id: c.attrs.acquisition_id).status == "success"
  end

  test "concurrent automatic workers consume exactly one attempt", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)

    results =
      1..8
      |> Task.async_stream(fn _ -> StorageWork.claim(work.id) end, max_concurrency: 8)
      |> Enum.map(fn {:ok, result} -> result end)

    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
    assert length(Enum.filter(results, &(&1 == {:error, :not_eligible}))) == 7
    assert Repo.get!(StorageWork, work.id).attempts == 1
  end

  test "concurrent manual scheduling writes one audit without resetting the exhausted budget",
       c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)

    Enum.reduce([60, 300, 1800, 0], DateTime.utc_now(), fn seconds, now ->
      {:ok, claim} = StorageWork.claim(work.id, now)
      {:ok, _} = StorageWork.finish(claim, {:error, :unavailable}, now)
      DateTime.add(now, seconds, :second)
    end)

    results =
      1..8
      |> Task.async_stream(fn index -> StorageWork.manual_retry(work.id, "operator-#{index}") end,
        max_concurrency: 8
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
    assert length(StorageWork.audit(work.id)) == 1

    assert {:ok, %{status: "completed", attempts: 4, manual_attempts: 1}} =
             StorageWork.recover(work.id, c.client)

    assert [%{status: "completed"}] = StorageWork.audit(work.id)
  end

  test "concurrent preparations keep one immutable provenance record", c do
    results =
      1..8
      |> Task.async_stream(
        fn index ->
          attrs =
            if rem(index, 2) == 0,
              do: c.attrs,
              else: %{c.attrs | url: "https://other.invalid/" <> c.attrs.acquisition_id}

          StorageWork.prepare(attrs, c.client)
        end,
        max_concurrency: 8
      )
      |> Enum.map(fn {:ok, result} -> result end)

    accepted = for {:ok, work} <- results, do: work
    assert length(accepted) == 4
    assert length(Enum.filter(results, &(&1 == {:error, :acquisition_conflict}))) == 4
    assert length(Enum.uniq_by(accepted, & &1.id)) == 1
  end
end
