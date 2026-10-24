defmodule Lens.Earnings.Original do
  use Ecto.Schema
  import Ecto.Changeset

  @limit 20_971_520
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "earnings_originals" do
    field(:sha256, :string)
    field(:byte_size, :integer)
    field(:key, :string)
    field(:endpoint, :string)
    field(:bucket, :string)
    field(:verified_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(original, attrs) when is_map(attrs) do
    original
    |> cast(attrs, [:sha256, :byte_size, :key, :endpoint, :bucket, :verified_at])
    |> validate_required([:sha256, :byte_size, :key, :endpoint, :bucket, :verified_at])
    |> validate_format(:sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_number(:byte_size, greater_than: 0, less_than_or_equal_to: @limit)
    |> unique_constraint(:sha256)
  end
end
