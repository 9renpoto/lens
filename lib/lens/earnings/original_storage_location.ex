defmodule Lens.Earnings.OriginalStorageLocation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "earnings_original_storage_locations" do
    field(:backend, :string)
    field(:key, :string)
    field(:endpoint, :string)
    field(:bucket, :string)
    field(:sha256, :string)
    field(:byte_size, :integer)
    field(:verified_at, :utc_datetime_usec)
    belongs_to(:original, Lens.Earnings.Original)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [
      :original_id,
      :backend,
      :key,
      :endpoint,
      :bucket,
      :sha256,
      :byte_size,
      :verified_at
    ])
    |> validate_required([:original_id, :backend, :sha256, :byte_size, :verified_at])
    |> validate_inclusion(:backend, ["postgresql", "rustfs"])
    |> validate_format(:sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_number(:byte_size, greater_than: 0, less_than_or_equal_to: 20_971_520)
    |> validate_backend_key()
    |> unique_constraint([:original_id, :backend])
    |> foreign_key_constraint(:original_id)
  end

  defp validate_backend_key(changeset) do
    backend = get_field(changeset, :backend)
    key = get_field(changeset, :key)
    endpoint = get_field(changeset, :endpoint)
    bucket = get_field(changeset, :bucket)

    if (backend == "postgresql" and is_nil(key) and is_nil(endpoint) and is_nil(bucket)) or
         (backend == "rustfs" and is_binary(key) and key != "" and
            is_binary(endpoint) and endpoint != "" and is_binary(bucket) and bucket != ""),
       do: changeset,
       else: add_error(changeset, :key, "does not match the storage backend")
  end
end
