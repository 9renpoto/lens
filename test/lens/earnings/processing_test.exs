defmodule Lens.Earnings.ProcessingTest do
  use Lens.DataCase

  alias Lens.Earnings
  alias Lens.Earnings.{Acquisition, Extraction, Extractions, Processing}

  defmodule FixtureExtractor do
    def extract("%PDF-success", _options),
      do: {:ok, %{version: "fixture 1", text: "売上高\n\n営業利益"}}

    def extract("%PDF-timeout", _options),
      do: {:error, %{version: "fixture 1", reason: "timeout"}}

    def extract("%PDF-bounded", _options),
      do: {:ok, %{version: "fixture 1", text: "Bounded output"}}
  end

  defmodule EmptyExtractor do
    def extract(_bytes, _options), do: {:ok, %{version: "empty fixture", text: " "}}
  end

  test "invalid extractor output and runner failures preserve retained bytes" do
    original = retain("%PDF-runner-failure").original
    assert {:ok, failure} = Processing.extract(original.id, extractor: EmptyExtractor)
    assert failure.status == "failed"
    assert failure.failure_reason == "invalid_text"
    assert failure.extractor_version == "empty fixture"

    for {python, reason} <- [
          {"/usr/bin/false", "process_error"},
          {"/usr/bin/true", "process_error"},
          {nil, "extractor_unavailable"}
        ] do
      assert {:ok, failure} =
               Processing.extract(original.id, python: python, executable: "/usr/bin/true")

      assert failure.status == "failed"
      assert failure.failure_reason == reason
    end

    assert Processing.retry_failed("invalid") == {:error, :not_found}
    assert Repo.aggregate(Acquisition, :count) == 1
    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-runner-failure"}
  end

  test "processing reads retained bytes, records outcomes, and never creates acquisitions" do
    success = retain("%PDF-success")
    failed = retain("%PDF-timeout")
    assert {:ok, text} = Processing.extract(success.original.id, extractor: FixtureExtractor)
    assert text.status == "succeeded"
    assert text.text == "売上高\n\n営業利益"
    assert text.original_id == success.original.id
    assert text.extractor_version == "fixture 1"
    assert text.extraction_options == %{"timeout_ms" => 20_000, "max_output_bytes" => 8_388_608}
    assert {:ok, failure} = Processing.extract(failed.original.id, extractor: FixtureExtractor)
    assert failure.status == "failed"
    assert failure.failure_reason == "timeout"
    assert failure.text == nil
    assert {:ok, retry} = Processing.extract(failed.original.id, extractor: FixtureExtractor)
    assert retry.id > failure.id
    assert Repo.aggregate(Acquisition, :count) == 2
    assert Earnings.original_bytes(failed.original.id) == {:ok, "%PDF-timeout"}
    assert Repo.aggregate(Extraction, :count) == 3
  end

  test "each attempt records the effective timeout and output limit before processing" do
    retained = retain("%PDF-bounded")

    assert {:ok, attempt} =
             Processing.extract(retained.original.id,
               extractor: FixtureExtractor,
               timeout_ms: 731,
               max_output_bytes: 12_345
             )

    assert Map.get(attempt, :extraction_options) == %{
             "timeout_ms" => 731,
             "max_output_bytes" => 12_345
           }
  end

  test "invalid bounds create no attempt or stored options" do
    retained = retain("%PDF-invalid-bounds")

    assert {:error, :invalid_options} =
             Processing.extract(retained.original.id,
               timeout_ms: 30_001,
               extractor: FixtureExtractor
             )

    assert Repo.aggregate(Extraction, :count) == 0
  end

  test "missing originals and invalid bounds create no extraction attempts" do
    assert {:error, :not_found} = Processing.extract(Ecto.UUID.generate())
    original = retain("%PDF-success").original

    for options <- [
          [timeout_ms: 0],
          [timeout_ms: 30_001],
          [max_output_bytes: 0],
          [max_output_bytes: 8_388_609]
        ] do
      assert {:error, :invalid_options} = Processing.extract(original.id, options)
    end

    assert Repo.aggregate(Extraction, :count) == 0
  end

  test "a missing process executable records a failure instead of leaving pending work" do
    original = retain("%PDF-success").original

    assert {:ok, failure} =
             Processing.extract(original.id,
               python: "/nonexistent/lens-python",
               executable: "/nonexistent/pdftotext"
             )

    assert failure.status == "failed"
    assert failure.failure_reason == "process_error"
    assert Repo.aggregate(Extraction, :count) == 1
    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-success"}
  end

  test "retry targets one latest failed original and regeneration requires a finite limit" do
    success = retain("%PDF-success").original
    failed = retain("%PDF-timeout").original

    assert {:error, :not_failed} =
             Processing.retry_failed(success.id, extractor: FixtureExtractor)

    assert {:ok, _} = Processing.extract(success.id, extractor: FixtureExtractor)
    assert {:ok, _} = Processing.extract(failed.id, extractor: FixtureExtractor)
    assert {:ok, retry} = Processing.retry_failed(failed.id, extractor: FixtureExtractor)
    assert retry.original_id == failed.id
    assert retry.status == "failed"

    for options <- [[], [limit: 0], [limit: 101]] do
      assert {:error, :invalid_options} = Processing.regenerate(options)
    end

    before_count = Repo.aggregate(Extraction, :count)
    assert {:ok, first} = Processing.regenerate(limit: 1, extractor: FixtureExtractor)
    assert length(first.results) == 1
    assert Repo.aggregate(Extraction, :count) == before_count + 1

    assert {:ok, second} =
             Processing.regenerate(
               limit: 1,
               after_original: first.next_after,
               extractor: FixtureExtractor
             )

    assert length(second.results) == 1
    refute first.next_after == second.next_after

    assert {:ok, %{results: [], next_after: nil}} =
             Processing.regenerate(
               limit: 1,
               after_original: second.next_after,
               extractor: FixtureExtractor
             )

    assert Repo.aggregate(Acquisition, :count) == 2
  end

  test "retry refuses a newly allocated pending attempt" do
    original = retain("%PDF-timeout").original
    assert {:ok, _failed} = Processing.extract(original.id, extractor: FixtureExtractor)
    assert {:ok, _pending} = Extractions.begin(original.id, "fixture", "2")

    assert {:error, :not_failed} =
             Processing.retry_failed(original.id, extractor: FixtureExtractor)

    assert Repo.aggregate(Extraction, :count) == 2
  end

  test "simultaneous retries allocate only one pending attempt" do
    original = retain("%PDF-timeout").original

    assert {:ok, %{status: "failed"}} =
             Processing.extract(original.id, extractor: FixtureExtractor)

    owner = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(owner, {:ready, self()})

          receive do
            :retry -> Processing.retry_failed(original.id, extractor: FixtureExtractor)
          end
        end)
      end

    for task <- tasks do
      assert_receive {:ready, pid}
      assert pid == task.pid
    end

    Enum.each(tasks, &send(&1.pid, :retry))
    results = Enum.map(tasks, &Task.await(&1, 5_000))
    assert Enum.count(results, &match?({:ok, %{status: "failed"}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :not_failed})) == 1
    assert Repo.aggregate(Extraction, :count) == 2
  end

  defp retain(bytes) do
    assert {:ok, result} =
             Earnings.record_success(%{
               bytes: bytes,
               acquisition_id: bytes,
               issuer_code: "6857",
               acquired_at: ~U[2026-09-27 01:00:00.000000Z],
               url: "https://example.test/original.pdf"
             })

    result
  end
end
