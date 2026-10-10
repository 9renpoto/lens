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

Repo.query!("UPDATE earnings_originals SET bytes = $1 WHERE id = $2", [
  bytes,
  Ecto.UUID.dump!(original.id)
])

assert both_waiting, "both selectors must reach the insert before the barrier is released"

for result <- results do
  assert {:ok, selected} = result
  assert selected.id == location.id
end

assert {:ok, selected} = OriginalStorage.read_location(original.id)
assert selected.id == location.id

Postgrex.query!(writer, "BEGIN", [])
Postgrex.query!(writer, "SELECT pg_advisory_xact_lock_shared(14501, 1)", [])

downgrade =
  Task.async(fn ->
    try do
      Ecto.Migrator.run(Repo, directory, :down, step: 1)
    rescue
      error -> {:error, error}
    end
  end)

waiting = wait_for_locks.(14501, 1)

id = Ecto.UUID.dump!(Ecto.UUID.generate())
restored_bytes = "%PDF-downgrade-#{Ecto.UUID.generate()}"
digest = Base.encode16(:crypto.hash(:sha256, restored_bytes), case: :lower)

if waiting do
  Postgrex.query!(
    writer,
    """
    INSERT INTO earnings_originals(id, sha256, byte_size, bytes, inserted_at)
    VALUES ($1, $2, $3, NULL, now())
    """,
    [id, digest, byte_size(restored_bytes)]
  )

  Postgrex.query!(writer, "COMMIT", [])
else
  Postgrex.query!(writer, "ROLLBACK", [])
end

result = Task.await(downgrade, 10_000)
assert waiting, "downgrade must acquire the exclusive storage fence before inspecting originals"
assert {:error, %Postgrex.Error{} = error} = result
assert Exception.message(error) =~ "RustFS-only originals remain"
assert Repo.query!("SELECT to_regclass('earnings_storage_controls') IS NOT NULL").rows == [[true]]

Repo.query!("UPDATE earnings_originals SET bytes = $1 WHERE id = $2", [restored_bytes, id])

Repo.query!(
  "UPDATE earnings_storage_controls SET rollback_active = TRUE, rollback_started_at = now()"
)

Ecto.Migrator.run(Repo, directory, :down, step: 1)

assert Repo.query!("SELECT bytes FROM earnings_originals WHERE id = $1", [id]).rows == [
         [restored_bytes]
       ]

assert Repo.query!("SELECT to_regclass('earnings_storage_controls') IS NULL").rows == [[true]]
GenServer.stop(writer)

IO.puts(
  "Concurrent selection is idempotent; downgrade fences writers and preserves restored bytes."
)
