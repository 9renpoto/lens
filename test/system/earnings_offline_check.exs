# Run with mix run --no-start inside an internal Docker network containing only PostgreSQL.
alias Lens.Earnings
alias Lens.Earnings.{Acquisition, Extraction, Original}
alias Lens.Repo

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Repo.start_link()
Ecto.Migrator.run(Repo, Application.app_dir(:lens, "priv/repo/migrations"), :up, all: true)

nil = Process.whereis(Lens.Ingestion.Scheduler)
nil = Process.whereis(LensWeb.Endpoint)

retain = fn name ->
  bytes = File.read!("test/fixtures/earnings-#{name}.pdf")

  {:ok, result} =
    Earnings.record_success(%{
      bytes: bytes,
      acquisition_id: "offline-#{name}",
      issuer_code: "6857",
      acquired_at: ~U[2026-09-27 01:00:00.000000Z],
      url: "https://publisher.invalid/earnings-#{name}.pdf",
      release: %{fiscal_year_end: ~D[2027-03-31], period: "q1", category: name}
    })

  {result, bytes}
end

{text, text_bytes} = retain.("text")
{image, image_bytes} = retain.("image")
Mix.Tasks.Lens.Earnings.Extract.run(["--original", text.original.id])
Mix.Tasks.Lens.Earnings.Extract.run(["--original", image.original.id])
successful = Lens.Earnings.Extractions.latest_success(text.original.id)
true = String.contains?(successful.text, "営業利益")
true = String.contains?(successful.text, "\n\n")
true = String.contains?(successful.extractor_version, "pdftotext version")
nil = Lens.Earnings.Extractions.latest_success(image.original.id)
failure = Repo.get_by!(Extraction, original_id: image.original.id)
"empty_output" = failure.failure_reason
Mix.Tasks.Lens.Earnings.Extract.run(["--retry", image.original.id])
Mix.Tasks.Lens.Earnings.Extract.run(["--regenerate", "--limit", "1"])
4 = Repo.aggregate(Extraction, :count)
2 = Repo.aggregate(Acquisition, :count)
2 = Repo.aggregate(Original, :count)
{:ok, ^text_bytes} = Earnings.original_bytes(text.original.id)
{:ok, ^image_bytes} = Earnings.original_bytes(image.original.id)
nil = Process.whereis(Lens.Ingestion.Scheduler)
nil = Process.whereis(LensWeb.Endpoint)
IO.puts("Offline PostgreSQL extraction, retry and bounded regeneration verified.")
