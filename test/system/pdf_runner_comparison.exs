# Developer-only migration measurement; Python is the retained reference.
Code.compile_file("lib/lens/earnings/pdf_extractor.ex")
alias Lens.Earnings.PDFExtractor
helper = Path.expand("priv/pdf_runner")
reference = System.fetch_env!("PDF_REFERENCE_RUNNER")
poppler = System.find_executable("pdftotext")

measure = fn operation ->
  started = System.monotonic_time(:microsecond)
  result = operation.()
  {result, (System.monotonic_time(:microsecond) - started) / 1000}
end

old = fn source ->
  {json, 0} = System.cmd("python3", [reference, poppler, source, "20", "8388608"])
  Jason.decode!(json)
end

new = fn source ->
  case PDFExtractor.extract(File.read!(source), helper: helper) do
    {:ok, value} -> %{"text" => value.text, "version" => value.version}
    {:error, value} -> %{"failure" => value.reason, "version" => value.version}
  end
end

for fixture <- ["text", "image"] do
  source = Path.expand("test/fixtures/earnings-#{fixture}.pdf")
  expected = old.(source)
  ^expected = new.(source)
end

root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
File.mkdir!(root)
source_fixture = Path.join(root, "input.pdf")
File.write!(source_fixture, "%PDF-fixture")

try do
  cases = [
    {"exact", "printf 1234 > \"$7\"", 4},
    {"overflow", "printf 12345 > \"$7\"; exit 1", 4},
    {"nonzero", "printf text > \"$7\"; exit 1", 1024},
    {"absent", "exit 0", 1024},
    {"blank", "printf ' \\f' > \"$7\"", 1024},
    {"nul", "printf 'text\\000' > \"$7\"", 1024},
    {"invalid_utf8", "printf '\\377' > \"$7\"", 1024}
  ]

  for {name, body, limit} <- cases do
    executable = Path.join(root, name)

    File.write!(
      executable,
      "#!/bin/sh\nif [ \"$1\" = -v ]; then echo fixture; exit 0; fi\n" <> body <> "\n"
    )

    File.chmod!(executable, 0o700)

    {json, 0} =
      System.cmd("python3", [reference, executable, source_fixture, "2", to_string(limit)])

    expected = Jason.decode!(json)

    actual =
      case PDFExtractor.extract("%PDF-fixture",
             helper: helper,
             executable: executable,
             timeout_ms: 2000,
             max_output_bytes: limit
           ) do
        {:ok, value} -> %{"text" => value.text, "version" => value.version}
        {:error, value} -> %{"failure" => value.reason, "version" => value.version}
      end

    ^expected = actual
  end

  IO.puts("Seven differential boundary cases passed.")
after
  File.rm_rf!(root)
end

source = Path.expand("test/fixtures/earnings-text.pdf")
for _ <- 1..5, do: {old.(source), new.(source)}

rows =
  for iteration <- 1..30 do
    {expected, old_ms} = measure.(fn -> old.(source) end)
    {^expected, new_ms} = measure.(fn -> new.(source) end)
    {_, old_start_ms} = measure.(fn -> System.cmd("python3", [reference]) end)
    {_, new_start_ms} = measure.(fn -> System.cmd(helper, []) end)

    %{
      iteration: iteration,
      old_ms: old_ms,
      new_ms: new_ms,
      old_start_ms: old_start_ms,
      new_start_ms: new_start_ms
    }
  end

percentile = fn values, fraction ->
  Enum.at(Enum.sort(values), ceil(length(values) * fraction) - 1)
end

summary =
  for key <- [:old_ms, :new_ms, :old_start_ms, :new_start_ms], into: %{} do
    values = Enum.map(rows, &Map.fetch!(&1, key))
    {key, %{median: percentile.(values, 0.5), p95: percentile.(values, 0.95)}}
  end

report = %{
  samples: rows,
  summary: summary,
  environment: %{
    architecture: to_string(:erlang.system_info(:system_architecture)),
    poppler: elem(System.cmd(poppler, ["-v"], stderr_to_stdout: true), 0)
  },
  warmup_runs: 5
}

File.write!(
  "docs/planning/v0.2/pdf-runner-samples.json",
  Jason.encode!(report, pretty: true) <> "\n"
)

IO.inspect(summary)
