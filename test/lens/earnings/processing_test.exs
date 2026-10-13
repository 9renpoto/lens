defmodule Lens.Earnings.ProcessingTest do
  use Lens.DataCase

  alias Lens.Earnings

  alias Lens.Earnings.{
    Acquisition,
    Extraction,
    Extractions,
    Original,
    OriginalStorage,
    Processing,
    RustFS
  }

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

    for {helper, reason} <- [
          {"/usr/bin/false", "process_error"},
          {"/usr/bin/true", "process_error"},
          {nil, "extractor_unavailable"}
        ] do
      assert {:ok, failure} =
               Processing.extract(original.id,
                 helper: helper,
                 platform: {:unix, :linux},
                 executable: "/usr/bin/true"
               )

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
    retained = retain("%PDF-timeout")

    assert {:ok, attempt} =
             Processing.extract(retained.original.id,
               extractor: FixtureExtractor,
               timeout_ms: 731,
               max_output_bytes: 12_345
             )

    assert attempt.status == "failed"
    assert attempt.failure_reason == "timeout"

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

  test "a missing helper records a failure instead of leaving pending work" do
    original = retain("%PDF-success").original

    assert {:ok, failure} =
             Processing.extract(original.id,
               helper: "/nonexistent/lens-helper",
               executable: "/nonexistent/pdftotext"
             )

    assert failure.status == "failed"
    assert failure.failure_reason == "extractor_unavailable"
    assert Repo.aggregate(Extraction, :count) == 1
    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-success"}
  end

  test "RustFS read failures create no extraction attempts or fallback reads" do
    original = retain("%PDF-rustfs-redirect").original
    stored_original = Repo.get!(Original, original.id)
    reference = storage_reference(stored_original)
    assert {:ok, _} = OriginalStorage.select_rustfs(stored_original, reference)

    client = rustfs_client(fn conn -> Plug.Conn.send_resp(conn, 307, "redirect") end)

    assert {:error, {:original_unavailable, id, {:http_error, 307}}} =
             Processing.extract(original.id, rustfs: client)

    assert id == original.id

    assert {:error, {:original_unavailable, ^id, :invalid_configuration}} =
             Processing.extract(original.id, rustfs: :invalid)

    assert Repo.aggregate(Extraction, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 1
  end

  test "verified RustFS-only bytes reach extraction before an attempt is allocated" do
    bytes = "%PDF-success"
    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    original =
      Repo.insert!(
        Original.rustfs_changeset(%Original{}, %{sha256: digest, byte_size: byte_size(bytes)})
      )

    assert {:ok, _} = OriginalStorage.select_rustfs(original, storage_reference(original))

    client =
      rustfs_client(fn conn ->
        assert conn.method == "GET"
        assert Repo.aggregate(Extraction, :count) == 0
        Plug.Conn.send_resp(conn, 200, bytes)
      end)

    assert {:ok, attempt} =
             Processing.extract(original.id, rustfs: client, extractor: FixtureExtractor)

    assert attempt.status == "succeeded"
    assert attempt.original_id == original.id
    assert Repo.get!(Original, original.id).bytes == nil
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "missing, corrupt and unavailable objects leave extraction history unchanged" do
    original = retain("%PDF-timeout").original
    assert {:ok, failed} = Processing.extract(original.id, extractor: FixtureExtractor)
    stored = Repo.get!(Original, original.id)
    assert {:ok, _} = OriginalStorage.select_rustfs(stored, storage_reference(stored))

    for {status, body, reason} <- [
          {404, "missing", :not_found},
          {200, "%PDF-corrupt", :integrity_error},
          {503, "unavailable", :unavailable}
        ] do
      client = rustfs_client(fn conn -> Plug.Conn.send_resp(conn, status, body) end)

      assert {:error, {:original_unavailable, id, ^reason}} =
               Processing.retry_failed(original.id, rustfs: client)

      assert id == original.id
      assert {:ok, batch} = Processing.regenerate(limit: 1, rustfs: client)
      assert [{^id, {:error, {:original_unavailable, ^id, ^reason}}}] = batch.results
      assert Repo.aggregate(Extraction, :count) == 1
      assert Repo.get!(Extraction, failed.id).failure_reason == "timeout"
    end

    client = rustfs_client(fn conn -> Plug.Conn.send_resp(conn, 200, "%PDF-timeout") end)

    assert {:ok, retry} =
             Processing.retry_failed(original.id, rustfs: client, extractor: FixtureExtractor)

    assert retry.id > failed.id
    assert Repo.aggregate(Extraction, :count) == 2
  end

  test "retry eligibility is checked before storage access" do
    original = retain("%PDF-success").original
    stored = Repo.get!(Original, original.id)
    assert {:ok, _} = OriginalStorage.select_rustfs(stored, storage_reference(stored))
    client = rustfs_client(fn _conn -> flunk("ineligible retry must not access storage") end)
    assert {:error, :not_failed} = Processing.retry_failed(original.id, rustfs: client)
    assert Repo.aggregate(Extraction, :count) == 0
  end

  test "PostgreSQL byte integrity is verified before extraction" do
    original =
      Repo.insert!(%Original{
        bytes: "%PDF-success",
        byte_size: 12,
        sha256: String.duplicate("0", 64)
      })

    assert {:error, {:original_unavailable, id, :integrity_error}} =
             Processing.extract(original.id, extractor: FixtureExtractor)

    assert id == original.id
    assert Repo.aggregate(Extraction, :count) == 0
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
    assert [{_original_id, {:ok, summary}}] = first.results
    refute Map.has_key?(summary, :text)
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

  test "a slow retry cannot target a newer failed attempt after retrieval" do
    original = retain("%PDF-timeout").original

    assert {:ok, %{status: "failed"}} =
             Processing.extract(original.id, extractor: FixtureExtractor)

    owner = self()

    stored = Repo.get!(Original, original.id)
    assert {:ok, _} = OriginalStorage.select_rustfs(stored, storage_reference(stored))

    slow =
      rustfs_client(fn conn ->
        send(owner, {:retrieving, self()})

        receive do
          :resume -> Plug.Conn.send_resp(conn, 200, "%PDF-timeout")
        after
          5_000 -> flunk("retrieval was not resumed")
        end
      end)

    task =
      Task.async(fn ->
        Processing.retry_failed(original.id, rustfs: slow, extractor: FixtureExtractor)
      end)

    assert_receive {:retrieving, reader}, 2_000
    fast = rustfs_client(fn conn -> Plug.Conn.send_resp(conn, 200, "%PDF-timeout") end)

    assert {:ok, %{status: "failed"}} =
             Processing.retry_failed(original.id, rustfs: fast, extractor: FixtureExtractor)

    send(reader, :resume)
    assert Task.await(task) == {:error, :retry_conflict}
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

  defp storage_reference(original) do
    %{
      key: "earnings/originals/sha256/#{original.sha256}.pdf",
      endpoint: "http://storage.test",
      bucket: "lens-originals",
      sha256: original.sha256,
      byte_size: original.byte_size
    }
  end

  defp rustfs_client(plug) do
    {:ok, client} =
      RustFS.new(
        endpoint: "http://storage.test",
        bucket: "lens-originals",
        access_key_id: "test-access",
        secret_access_key: "test-secret"
      )

    %{client | request: Req.merge(client.request, plug: plug)}
  end
end
