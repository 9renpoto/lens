defmodule Lens.Repo.Migrations.CreateEarningsStorageWork do
  use Ecto.Migration

  def change do
    create table(:earnings_storage_work, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:acquisition_id, :string, null: false)
      add(:issuer_code, :string, null: false)
      add(:url, :text, null: false)
      add(:acquired_at, :utc_datetime_usec, null: false)
      add(:release, :map)
      add(:endpoint, :text, null: false)
      add(:bucket, :string, null: false)
      add(:key, :text, null: false)
      add(:sha256, :string, null: false)
      add(:byte_size, :integer, null: false)
      add(:bytes, :binary)
      add(:status, :string, null: false, default: "pending")
      add(:attempts, :integer, null: false, default: 0)
      add(:manual_attempts, :integer, null: false, default: 0)
      add(:manual_pending, :boolean, null: false, default: false)
      add(:last_failure, :string)
      add(:next_attempt_at, :utc_datetime_usec)
      add(:lease_token, :binary_id)
      add(:lease_expires_at, :utc_datetime_usec)
      add(:active_audit_id, :binary_id)
      add(:acquisition_record_id, references(:earnings_acquisitions, type: :binary_id))
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:earnings_storage_work, [:acquisition_id]))
    create(index(:earnings_storage_work, [:status, :next_attempt_at]))

    create(
      constraint(:earnings_storage_work, :storage_work_state,
        check:
          "status IN ('pending', 'running', 'completed', 'exhausted', 'attention') AND attempts BETWEEN 0 AND 4 AND manual_attempts >= 0 AND byte_size BETWEEN 1 AND 20971520 AND ((status = 'completed' AND bytes IS NULL AND acquisition_record_id IS NOT NULL) OR (status != 'completed' AND bytes IS NOT NULL AND octet_length(bytes) = byte_size)) AND ((status = 'running' AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL) OR (status != 'running' AND lease_token IS NULL AND lease_expires_at IS NULL))"
      )
    )

    create table(:earnings_storage_retry_audits, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:work_id, references(:earnings_storage_work, type: :binary_id), null: false)
      add(:operator, :string, null: false)
      add(:status, :string, null: false)
      add(:requested_at, :utc_datetime_usec, null: false)
      add(:finished_at, :utc_datetime_usec)
      add(:failure, :string)
    end

    create(index(:earnings_storage_retry_audits, [:work_id, :requested_at]))
  end
end
