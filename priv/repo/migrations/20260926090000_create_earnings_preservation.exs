defmodule Lens.Repo.Migrations.CreateEarningsPreservation do
  use Ecto.Migration

  def change do
    create table(:earnings_releases, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:issuer_code, :string, null: false)
      add(:fiscal_year_end, :date, null: false)
      add(:period, :string, null: false)
      add(:category, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:earnings_releases, [:issuer_code, :fiscal_year_end, :period, :category]))

    create(
      constraint(:earnings_releases, :earnings_releases_period_check,
        check: "period IN ('q1', 'q2', 'q3', 'full_year')"
      )
    )

    create table(:earnings_originals, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:sha256, :string, null: false)
      add(:byte_size, :integer, null: false)
      add(:bytes, :binary, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:earnings_originals, [:sha256]))

    create(
      constraint(:earnings_originals, :earnings_originals_size_check,
        check: "byte_size = octet_length(bytes) AND byte_size <= 20971520 AND byte_size > 0"
      )
    )

    create table(:earnings_acquisitions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:acquisition_id, :string, null: false)
      add(:issuer_code, :string, null: false)
      add(:url, :text, null: false)
      add(:acquired_at, :utc_datetime_usec, null: false)
      add(:status, :string, null: false)
      add(:failure_reason, :string)
      add(:original_id, references(:earnings_originals, type: :binary_id))
      add(:release_id, references(:earnings_releases, type: :binary_id))
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:earnings_acquisitions, [:acquisition_id]))
    create(index(:earnings_acquisitions, [:release_id, :acquired_at]))
    create(index(:earnings_acquisitions, [:issuer_code, :acquired_at]))

    create(
      constraint(:earnings_acquisitions, :earnings_acquisitions_status_check,
        check:
          "(status = 'success' AND original_id IS NOT NULL AND failure_reason IS NULL) OR " <>
            "(status = 'failed' AND original_id IS NULL AND release_id IS NULL AND failure_reason IS NOT NULL)"
      )
    )
  end
end
