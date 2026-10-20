# Run only against an isolated disposable database; this check seeds and updates test work.
Application.ensure_all_started(:ecto_sql)
Application.ensure_all_started(:postgrex)
config = Application.fetch_env!(:lens, Lens.Repo)
Application.put_env(:lens, Lens.Repo, Keyword.put(config, :pool, DBConnection.ConnectionPool))
{:ok, repo} = Lens.Repo.start_link()
Process.unlink(repo)
directory = Application.app_dir(:lens, "priv/repo/migrations")
Ecto.Migrator.run(Lens.Repo, directory, :up, to: 20_261_015_000_000)
ExUnit.start(seed: 0)

defmodule Lens.RecoveryRetirementCheck do
  use ExUnit.Case, async: false
  alias Lens.Earnings.{Acquisition, HTTPCheck, Original}
  alias Lens.Repo

  test "forward removal refuses retained payloads and preserves completed original and HTTP history" do
    attrs = %{
      check_id: Ecto.UUID.generate(),
      issuer_code: "7203",
      kind: :pdf,
      url: "https://publisher.invalid/report.pdf",
      checked_at: DateTime.utc_now(),
      metadata: %{anchor_text: "Historical results"},
      result: %{
        outcome: :success,
        final_url: "https://publisher.invalid/report.pdf",
        bytes: "%PDF-migration",
        http_status: 200,
        requests: 1,
        retryable: false,
        headers: %{}
      }
    }

    {:ok, check} = Lens.Earnings.HTTPHistory.record(attrs)
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    original = Repo.get!(Original, acquisition.original_id)
    id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO earnings_storage_work
        (id, acquisition_id, issuer_code, url, acquired_at, endpoint, bucket, key,
         sha256, byte_size, bytes, status, inserted_at, updated_at)
      VALUES ($1, 'pending-migration', '7203', 'https://publisher.invalid/pending.pdf', NOW(),
              'http://storage.invalid', 'lens-test', $2, $3, $4, $5, 'pending', NOW(), NOW())
      """,
      [
        Ecto.UUID.dump!(id),
        "earnings/originals/sha256/#{original.sha256}.pdf",
        original.sha256,
        original.byte_size,
        "%PDF-migration"
      ]
    )

    directory = Application.app_dir(:lens, "priv/repo/migrations")

    assert_raise Postgrex.Error, ~r/unfinished storage work prevents recovery retirement/, fn ->
      Ecto.Migrator.run(Repo, directory, :up, all: true)
    end

    assert %{rows: [["%PDF-migration"]]} =
             Repo.query!("SELECT bytes FROM earnings_storage_work WHERE id = $1", [
               Ecto.UUID.dump!(id)
             ])

    assert Repo.get!(Original, original.id) == original

    # Simulate completion only for this disposable fixture, without deleting its original.
    Repo.query!(
      "UPDATE earnings_storage_work SET status = 'completed', bytes = NULL, acquisition_record_id = $2 WHERE id = $1",
      [Ecto.UUID.dump!(id), Ecto.UUID.dump!(acquisition.id)]
    )

    Ecto.Migrator.run(Repo, directory, :up, all: true)

    assert %{rows: [[nil, nil]]} =
             Repo.query!(
               "SELECT to_regclass('earnings_storage_work'), to_regclass('earnings_storage_retry_audits')"
             )

    assert Repo.get!(Acquisition, acquisition.id) == acquisition
    assert Repo.get!(HTTPCheck, check.id) == check
    assert Repo.get!(Original, original.id) == original
    assert Lens.Earnings.original_bytes(original.id) == {:ok, "%PDF-migration"}
  end
end
