defmodule Lens.Earnings.OriginalReadLocation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "earnings_original_read_locations" do
    belongs_to(:original, Lens.Earnings.Original, primary_key: true)
    belongs_to(:location, Lens.Earnings.OriginalStorageLocation)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(selection, attrs) do
    selection
    |> cast(attrs, [:original_id, :location_id])
    |> validate_required([:original_id, :location_id])
    |> foreign_key_constraint(:original_id)
    |> foreign_key_constraint(:location_id, name: :earnings_original_read_location_match)
  end
end
