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
end
