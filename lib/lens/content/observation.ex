defmodule Lens.Content.Observation do
  use Ecto.Schema

  import Ecto.Changeset

  @fetch_metadata_limit_bytes 4_096
  @acquisition_metadata_limit_bytes 16_384
  @sensitive_metadata_keys ~w(authorization cookie password token)
  @feed_formats ~w(rss_2_0 atom rss_1_0 unknown)
  @acquisition_kinds ~w(direct conversion_service rsshub unknown)
  @publisher_authorities ~w(official third_party unknown)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "A successful observation of a document from one source."
  @type t :: %__MODULE__{
          id: binary() | nil,
          source_id: binary() | nil,
          document_id: binary() | nil,
          observed_at: DateTime.t() | nil,
          content_hash: String.t() | nil,
          entry_url: String.t() | nil,
          primary_source_url: String.t() | nil,
          reported_published_at: DateTime.t() | nil
        }

  schema "observations" do
    field(:observed_at, :utc_datetime_usec)
    field(:content_hash, :string)
    field(:fetch_metadata, :map, default: %{})
    field(:entry_url, :string)
    field(:primary_source_url, :string)
    field(:feed_format, :string, default: "unknown")
    field(:acquisition_kind, :string, default: "unknown")
    field(:publisher_authority, :string, default: "unknown")
    field(:acquisition_metadata_snapshot, :map, default: %{})
    field(:reported_published_at, :utc_datetime_usec)

    belongs_to(:source, Lens.Content.Source)
    belongs_to(:document, Lens.Content.Document)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(observation, attrs) do
    observation
    |> cast(attrs, [
      :source_id,
      :document_id,
      :observed_at,
      :content_hash,
      :fetch_metadata,
      :entry_url,
      :primary_source_url,
      :feed_format,
      :acquisition_kind,
      :publisher_authority,
      :acquisition_metadata_snapshot,
      :reported_published_at
    ])
    |> validate_required([:source_id, :document_id, :observed_at, :content_hash])
    |> validate_length(:content_hash, is: 64)
    |> validate_inclusion(:feed_format, @feed_formats)
    |> validate_inclusion(:acquisition_kind, @acquisition_kinds)
    |> validate_inclusion(:publisher_authority, @publisher_authorities)
    |> validate_url(:entry_url)
    |> validate_url(:primary_source_url)
    |> validate_fetch_metadata()
    |> validate_acquisition_metadata_snapshot()
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:source_id, :document_id, :observed_at])
  end

  defp validate_fetch_metadata(changeset) do
    validate_bounded_metadata(changeset, :fetch_metadata, @fetch_metadata_limit_bytes)
  end

  defp validate_acquisition_metadata_snapshot(changeset) do
    validate_bounded_metadata(
      changeset,
      :acquisition_metadata_snapshot,
      @acquisition_metadata_limit_bytes
    )
  end

  defp validate_bounded_metadata(changeset, field, limit_bytes) do
    validate_change(changeset, field, fn ^field, metadata ->
      cond do
        not is_map(metadata) ->
          [{field, "must be a map"}]

        Enum.any?(Map.keys(metadata), &(to_string(&1) in @sensitive_metadata_keys)) ->
          [{field, "must not contain credentials"}]

        byte_size(Jason.encode!(metadata)) > limit_bytes ->
          [{field, "is too large"}]

        true ->
          []
      end
    end)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      uri = URI.parse(value)

      if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.userinfo == nil do
        []
      else
        [{field, "must be an absolute HTTP(S) URL without credentials"}]
      end
    end)
  end
end
