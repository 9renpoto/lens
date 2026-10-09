defmodule Lens.Earnings.StorageRetryAudit do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "earnings_storage_retry_audits" do
    field(:work_id, :binary_id)
    field(:operator, :string)
    field(:status, :string)
    field(:requested_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)
    field(:failure, :string)
  end
end
