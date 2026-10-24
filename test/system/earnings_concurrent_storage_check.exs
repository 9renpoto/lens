# Run against an empty disposable database with MIX_ENV=test mix run --no-start.
import ExUnit.Assertions
alias Lens.{Earnings, Repo}

Lens.Release.prepare()
{:ok, _} = Repo.start_link(pool: DBConnection.ConnectionPool)

{:ok, writer} =
  Postgrex.start_link(
    Keyword.take(Repo.config(), [:hostname, :port, :database, :username, :password])
  )

Repo.query!("""
CREATE FUNCTION test_original_barrier() RETURNS trigger AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(213214, 1);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
""")

Repo.query!(
  "CREATE TRIGGER test_original_barrier BEFORE INSERT ON earnings_originals FOR EACH ROW EXECUTE FUNCTION test_original_barrier()"
)

Postgrex.query!(writer, "SELECT pg_advisory_lock(213214, 1)", [])
bytes = "%PDF-concurrent-original"
digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

reference = %{
  endpoint: "http://storage.example.test",
  bucket: "fixture-originals",
  key: "earnings/originals/sha256/#{digest}.pdf",
  sha256: digest,
  byte_size: byte_size(bytes)
}

attrs = %{
  issuer_code: "issuer-alpha",
  url: "https://publisher.example.test/report.pdf",
  acquired_at: DateTime.utc_now(),
  bytes: bytes,
  storage_reference: reference
}

tasks =
  for id <- ["first", "second"],
      do: Task.async(fn -> Earnings.record_success(Map.put(attrs, :acquisition_id, id)) end)

both_waiting =
  Enum.reduce_while(1..250, false, fn _, _ ->
    result =
      Postgrex.query!(
        writer,
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted AND classid = 213214::oid AND objid = 1 AND database = (SELECT oid FROM pg_database WHERE datname = current_database())",
        []
      )

    if hd(hd(result.rows)) == 2,
      do: {:halt, true},
      else:
        (
          Process.sleep(20)
          {:cont, false}
        )
  end)

Postgrex.query!(writer, "SELECT pg_advisory_unlock(213214, 1)", [])
results = Enum.map(tasks, &Task.await(&1, 10_000))
Repo.query!("DROP TRIGGER test_original_barrier ON earnings_originals")
Repo.query!("DROP FUNCTION test_original_barrier()")
assert both_waiting, "both writers must reach original insertion"
assert [{:ok, first}, {:ok, second}] = results
assert first.original.id == second.original.id
assert Repo.aggregate(Lens.Earnings.Original, :count) == 1
assert Repo.aggregate(Lens.Earnings.Acquisition, :count) == 2
assert Map.take(first.original, Map.keys(reference)) == reference
GenServer.stop(writer)
IO.puts("Concurrent original persistence deduplicates bytes and retains two acquisitions.")
