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
