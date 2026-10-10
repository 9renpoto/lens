# Run against an empty disposable database with mix run --no-start.
import ExUnit.Assertions
alias Lens.Repo
alias Lens.Earnings.{Original, OriginalStorage, OriginalStorageLocation}

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Repo.start_link(pool: DBConnection.ConnectionPool)
directory = Application.app_dir(:lens, "priv/repo/migrations")
Ecto.Migrator.run(Repo, directory, :up, all: true)

{:ok, writer} =
  Postgrex.start_link(
    Keyword.take(Repo.config(), [:hostname, :port, :database, :username, :password])
  )

wait_for_locks = fn lock_class, expected ->
  Enum.reduce_while(1..250, false, fn _, _ ->
    result =
      Postgrex.query!(
        writer,
        """
        SELECT count(*) FROM pg_locks
        WHERE locktype = 'advisory' AND mode = 'ExclusiveLock' AND NOT granted
          AND classid = $1::oid AND objid = 1 AND objsubid = 2
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
        """,
        [lock_class]
      )

    if hd(hd(result.rows)) >= expected do
      {:halt, true}
    else
      Process.sleep(20)
      {:cont, false}
    end
  end)
end

# Force both selectors to observe an absent selection before either insert completes.
bytes = "%PDF-selection-#{Ecto.UUID.generate()}"
digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

original =
  %Original{}
  |> Original.rustfs_changeset(%{sha256: digest, byte_size: byte_size(bytes)})
  |> Repo.insert!()

reference = %{
  key: "earnings/originals/sha256/#{digest}.pdf",
  sha256: digest,
  byte_size: byte_size(bytes),
  endpoint: "http://storage.test",
  bucket: "lens-originals"
}

location =
  %OriginalStorageLocation{}
  |> OriginalStorageLocation.changeset(
    Map.merge(reference, %{
      original_id: original.id,
      backend: "rustfs",
      verified_at: DateTime.utc_now()
    })
  )
  |> Repo.insert!()

Repo.query!("""
CREATE FUNCTION test_read_location_barrier() RETURNS trigger AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(14502, 1);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
""")

Repo.query!("""
CREATE TRIGGER test_read_location_barrier BEFORE INSERT ON earnings_original_read_locations
FOR EACH ROW EXECUTE FUNCTION test_read_location_barrier();
""")

Postgrex.query!(writer, "SELECT pg_advisory_lock(14502, 1)", [])

selectors =
  for _ <- 1..2 do
    Task.async(fn ->
      try do
        OriginalStorage.select_rustfs(original, reference)
      rescue
        error -> {:error, error}
      end
    end)
  end

both_waiting = wait_for_locks.(14502, 2)
Postgrex.query!(writer, "SELECT pg_advisory_unlock(14502, 1)", [])
results = Enum.map(selectors, &Task.await(&1, 10_000))
Repo.query!("DROP TRIGGER test_read_location_barrier ON earnings_original_read_locations")
Repo.query!("DROP FUNCTION test_read_location_barrier()")

assert both_waiting, "both selectors must reach the insert before the barrier is released"

for result <- results do
  assert {:ok, selected} = result
  assert selected.id == location.id
end

assert {:ok, selected} = OriginalStorage.read_location(original.id)
assert selected.id == location.id

GenServer.stop(writer)

IO.puts("Concurrent storage selection is idempotent.")
