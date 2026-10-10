# Run against an empty disposable database with mix run --no-start.
import ExUnit.Assertions
alias Lens.Repo

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Repo.start_link(pool: DBConnection.ConnectionPool)
directory = Application.app_dir(:lens, "priv/repo/migrations")
Ecto.Migrator.run(Repo, directory, :up, all: true)

{:ok, writer} =
  Postgrex.start_link(
    Keyword.take(Repo.config(), [:hostname, :port, :database, :username, :password])
  )

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

waiting =
  Enum.reduce_while(1..250, false, fn _, _ ->
    result =
      Postgrex.query!(
        writer,
        """
        SELECT EXISTS (
          SELECT 1 FROM pg_locks
          WHERE locktype = 'advisory' AND mode = 'ExclusiveLock' AND NOT granted
            AND classid = 14501 AND objid = 1 AND objsubid = 2
            AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
        )
        """,
        []
      )

    if result.rows == [[true]] do
      {:halt, true}
    else
      Process.sleep(20)
      {:cont, false}
    end
  end)

id = Ecto.UUID.dump!(Ecto.UUID.generate())
digest = Base.encode16(:crypto.hash(:sha256, "x"), case: :lower)

if waiting do
  Postgrex.query!(
    writer,
    """
    INSERT INTO earnings_originals(id, sha256, byte_size, bytes, inserted_at)
    VALUES ($1, $2, 1, NULL, now())
    """,
    [id, digest]
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

Repo.query!("UPDATE earnings_originals SET bytes = $1 WHERE id = $2", ["x", id])

Repo.query!(
  "UPDATE earnings_storage_controls SET rollback_active = TRUE, rollback_started_at = now()"
)

Ecto.Migrator.run(Repo, directory, :down, step: 1)
assert Repo.query!("SELECT bytes FROM earnings_originals WHERE id = $1", [id]).rows == [["x"]]
assert Repo.query!("SELECT to_regclass('earnings_storage_controls') IS NULL").rows == [[true]]
GenServer.stop(writer)

IO.puts(
  "Storage downgrade fences live writers, rejects RustFS-only originals, and preserves restored bytes."
)
