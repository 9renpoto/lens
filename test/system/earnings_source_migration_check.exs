# Run against an empty disposable database with MIX_ENV=test mix run --no-start.
alias Lens.Analysis
alias Lens.Earnings.{HTTPHistory, Sources, SourceCatalog}
alias Lens.Repo

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Repo.start_link()
directory = Application.app_dir(:lens, "priv/repo/migrations")
Ecto.Migrator.run(Repo, directory, :up, to: 20_261_002_000_000)

input = fn id, issuer, kind, outcome, bytes ->
  %{
    check_id: id,
    issuer_code: issuer,
    kind: kind,
    url: "https://publisher.invalid/old",
    checked_at: ~U[2026-10-02 01:00:00.000000Z],
    result: %{
      outcome: outcome,
      bytes: bytes,
      final_url: "https://publisher.invalid/old",
      http_status: if(outcome == :success, do: 200, else: 503),
      requests: 1,
      headers: %{},
      retryable: outcome != :success,
      failure_reason: if(outcome != :success, do: :http_error)
    }
  }
end

for {id, kind, outcome, bytes} <- [
      {"old-listing", :listing, :success, "<html>old listing</html>"},
      {"old-pdf", :pdf, :success, "%PDF-original bytes"},
      {"old-failure", :pdf, :failed, nil}
    ] do
  {:ok, _} = HTTPHistory.record(input.(id, "6857", kind, outcome, bytes))
end

snapshot = fn ->
  for table <- [
        "earnings_originals",
        "earnings_acquisitions",
        "earnings_http_checks",
        "analysis_targets"
      ] do
    {table, Repo.query!("SELECT * FROM #{table} ORDER BY id").rows}
  end
end

before = snapshot.()
Ecto.Migrator.run(Repo, directory, :up, all: true)
^before = snapshot.()
[] = SourceCatalog.all()

{:ok, target} =
  Analysis.create_target(%{
    security_code: "7203",
    market: "TSE",
    display_name: "Synthetic target",
    sector: "Test",
    active: false
  })

{:ok, source} = Sources.create(target, %{listing_url: "https://publisher.invalid/new"})
true = source.enabled

{:ok, _} =
  Sources.create(target, %{listing_url: "https://publisher.invalid/corrections", enabled: false})

{:ok, _} =
  Sources.update(source, %{listing_url: "https://publisher.invalid/changed", enabled: false})

^before = snapshot.() |> List.keyreplace("analysis_targets", 0, {"analysis_targets", []})

# Legacy persistence callers need no newly registered source, including former pilot issuers.
{:ok, _} =
  HTTPHistory.record(
    input.("legacy-after-migration", "9983", :listing, :success, "<html>legacy</html>")
  )

{:ok, _} =
  HTTPHistory.record(input.("registered-listing", "7203", :listing, :success, "<html>new</html>"))

{:ok, check} =
  HTTPHistory.record(input.("registered-pdf", "7203", :pdf, :success, "%PDF-new bytes"))

acquisition = Repo.get!(Lens.Earnings.Acquisition, check.acquisition_id)
{:ok, "%PDF-new bytes"} = Lens.Earnings.original_bytes(acquisition.original_id)

# Configuration updates must not permit mutation or deletion of historical HTTP facts.
for sql <- [
      "UPDATE earnings_http_checks SET issuer_code = '7203' WHERE check_id = 'old-listing'",
      "DELETE FROM earnings_http_checks WHERE check_id = 'old-listing'"
    ] do
  try do
    Repo.query!(sql)
    raise "Historical HTTP facts were mutable"
  rescue
    error in Postgrex.Error ->
      true = String.contains?(error.postgres.message, "immutable")
  end
end

IO.puts(
  "Source forward migration preserved all prior rows and bytes, imported no targets or sources, accepted non-pilot checks, retained legacy callers, and kept history immutable."
)
