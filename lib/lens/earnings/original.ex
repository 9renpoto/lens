defmodule Lens.Earnings.Original do
  use Ecto.Schema
  import Ecto.Changeset

  @limit 20_971_520
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "earnings_originals" do
    field(:sha256, :string)
    field(:byte_size, :integer)
    field(:bytes, :binary, redact: true)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(original, bytes) when is_binary(bytes) do
    original
    |> change(%{
      sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower),
      byte_size: byte_size(bytes),
      bytes: bytes
    })
    |> validate_number(:byte_size, greater_than: 0, less_than_or_equal_to: @limit)
    |> unique_constraint(:sha256)
  end

  def rustfs_changeset(original, attrs) when is_map(attrs) do
    original
    |> cast(attrs, [:id, :sha256, :byte_size])
    |> put_change(:bytes, nil)
    |> validate_required([:sha256, :byte_size])
    |> validate_format(:sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_number(:byte_size, greater_than: 0, less_than_or_equal_to: @limit)
    |> unique_constraint(:sha256)
  end
end
