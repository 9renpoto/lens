# Run with release eval inside an internal Docker network containing only a disposable PostgreSQL 18 database.
Logger.configure(level: :warning)
alias Lens.Earnings
alias Lens.Earnings.{Acquisition, Extraction, Original}
alias Lens.Repo
import Ecto.Query

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Repo.start_link()
Ecto.Migrator.run(Repo, Application.app_dir(:lens, "priv/repo/migrations"), :up, all: true)

nil = Process.whereis(Lens.Ingestion.Scheduler)
nil = Process.whereis(LensWeb.Endpoint)

retain = fn name ->
  bytes = File.read!("/source/test/fixtures/earnings-#{name}.pdf")

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

cli = fn args ->
  {output, 0} = System.cmd("/app/bin/lens-earnings-extract", args)
  Jason.decode!(output)
end

{text, text_bytes} = retain.("text")
{image, image_bytes} = retain.("image")
cli.(["--original", text.original.id])
cli.(["--original", image.original.id])
successful = Lens.Earnings.Extractions.latest_success(text.original.id)
true = String.contains?(successful.text, "営業利益")
true = String.contains?(successful.text, "\n\n")
true = String.contains?(successful.extractor_version, "pdftotext version")
{:ok, [search_result]} = Lens.Search.search("営業利益")
true = search_result.id == text.release.id
true = search_result.extraction_id == successful.id
:ok = Lens.Search.rebuild(batch_size: 1)
{:ok, [^search_result]} = Lens.Search.search("営業利益")
nil = Lens.Earnings.Extractions.latest_success(image.original.id)
failure = Repo.get_by!(Extraction, original_id: image.original.id)
"empty_output" = failure.failure_reason
cli.(["--retry", image.original.id])
cli.(["--regenerate", "--limit", "1"])
4 = Repo.aggregate(Extraction, :count)
2 = Repo.aggregate(Acquisition, :count)
2 = Repo.aggregate(Original, :count)
{:ok, ^text_bytes} = Earnings.original_bytes(text.original.id)
{:ok, ^image_bytes} = Earnings.original_bytes(image.original.id)
nil = Process.whereis(Lens.Ingestion.Scheduler)
nil = Process.whereis(LensWeb.Endpoint)

before_failure = Lens.Earnings.Extractions.latest_success(text.original.id)

%{"status" => "failed", "failure_reason" => "output_limit"} =
  cli.(["--original", text.original.id, "--max-output-bytes", "1"])

^before_failure = Lens.Earnings.Extractions.latest_success(text.original.id)
^successful = Repo.get!(Extraction, successful.id)
{:ok, ^text_bytes} = Earnings.original_bytes(text.original.id)
2 = Repo.aggregate(Acquisition, :count)
0 = Repo.aggregate(from(e in Extraction, where: e.status == "pending"), :count)

for attempt <- Repo.all(Extraction) do
  "Lens.Earnings.PDFExtractor" = attempt.extractor
  true = String.contains?(attempt.extractor_version, "pdftotext version")
  true = Map.has_key?(attempt.extraction_options, "timeout_ms")
  true = Map.has_key?(attempt.extraction_options, "max_output_bytes")
end

{:ok, [_]} = Lens.Search.search("営業利益")

IO.puts(
  "Python-free release CLI originals, retry, bounded regeneration, failure history and CJK search verified."
)
