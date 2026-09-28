# Run against an empty disposable PostgreSQL database with mix run --no-start.
alias Lens.Earnings
alias Lens.Repo

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Repo.start_link()
directory = Application.app_dir(:lens, "priv/repo/migrations")
Ecto.Migrator.run(Repo, directory, :up, to: 20_260_927_090_000)

{:ok, retained} =
  Earnings.record_success(%{
    bytes: "%PDF-migration",
    acquisition_id: "migration",
    issuer_code: "6857",
    acquired_at: ~U[2026-09-27 01:00:00.000000Z],
    url: "https://publisher.invalid/migration.pdf",
    release: %{fiscal_year_end: ~D[2027-03-31], period: "q1", category: "earnings_release"}
  })

dense = Enum.map_join(1..100_000, " ", &"word#{&1}")
marker = "\n\n移行末尾マーカー"
body = binary_part(String.duplicate(dense <> " ", 9), 0, 8_388_608 - byte_size(marker)) <> marker

Repo.query!(
  """
  INSERT INTO earnings_extractions(original_id, extractor, extractor_version, status, text, finished_at, inserted_at)
  VALUES ($1, 'fixture', '1', 'succeeded', $2, NOW(), NOW())
  """,
  [Ecto.UUID.dump!(retained.original.id), body]
)

Ecto.Migrator.run(Repo, directory, :up, all: true)

%{rows: [[^body, true]]} =
  Repo.query!("SELECT text, search_vector IS NULL FROM earnings_extractions")

{:ok, %{results: [result], full_text_complete: false}} = Lens.Search.search_response("移行末尾マーカー")
true = result.id == retained.release.id
"substring" = result.search_mode
:ok = Lens.Search.rebuild(batch_size: 1)
{:ok, %{results: [^result], full_text_complete: false}} = Lens.Search.search_response("移行末尾マーカー")
{:ok, "%PDF-migration"} = Earnings.original_bytes(retained.original.id)
IO.puts("Pre-existing 8 MiB successful extraction migration and rebuild verified.")
