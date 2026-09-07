defmodule Lens.Content.Observation do
  use Ecto.Schema

  import Ecto.Changeset

  @fetch_metadata_limit_bytes 4_096
  @sensitive_metadata_keys ~w(authorization cookie password token)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "observations" do
    field(:observed_at, :utc_datetime_usec)
    field(:content_hash, :string)
    field(:fetch_metadata, :map, default: %{})

    belongs_to(:source, Lens.Content.Source)
    belongs_to(:document, Lens.Content.Document)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(observation, attrs) do
    observation
    |> cast(attrs, [:source_id, :document_id, :observed_at, :content_hash, :fetch_metadata])
    |> validate_required([:source_id, :document_id, :observed_at, :content_hash])
    |> validate_length(:content_hash, is: 64)
    |> validate_fetch_metadata()
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:source_id, :document_id, :observed_at])
  end

  defp validate_fetch_metadata(changeset) do
    validate_change(changeset, :fetch_metadata, fn :fetch_metadata, metadata ->
      cond do
        not is_map(metadata) ->
          [fetch_metadata: "must be a map"]

        Enum.any?(Map.keys(metadata), &(to_string(&1) in @sensitive_metadata_keys)) ->
          [fetch_metadata: "must not contain credentials"]

        byte_size(Jason.encode!(metadata)) > @fetch_metadata_limit_bytes ->
          [fetch_metadata: "is too large"]

        true ->
          []
      end
    end)
  end
end
