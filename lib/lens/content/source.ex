defmodule Lens.Content.Source do
  use Ecto.Schema

  import Ecto.Changeset

  @source_types ~w(rss atom rsshub)
  @metadata_limit_bytes 16_384
  @sensitive_metadata_keys ~w(authorization cookie password token)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "A configured endpoint and its ingestion state."
  @type t :: %__MODULE__{
          id: binary() | nil,
          source_type: String.t() | nil,
          endpoint_url: String.t() | nil,
          etag: String.t() | nil,
          last_modified: String.t() | nil
        }

  schema "sources" do
    field(:source_type, :string)
    field(:endpoint_url, :string)
    field(:title, :string)
    field(:enabled, :boolean, default: true)
    field(:poll_interval_seconds, :integer)
    field(:next_fetch_at, :utc_datetime_usec)
    field(:etag, :string)
    field(:last_modified, :string)
    field(:last_attempt_at, :utc_datetime_usec)
    field(:last_success_at, :utc_datetime_usec)
    field(:last_error, :string)
    field(:failure_count, :integer, default: 0)
    field(:metadata, :map, default: %{})

    has_many(:observations, Lens.Content.Observation)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :source_type,
      :endpoint_url,
      :title,
      :enabled,
      :poll_interval_seconds,
      :next_fetch_at,
      :etag,
      :last_modified,
      :last_attempt_at,
      :last_success_at,
      :last_error,
      :failure_count,
      :metadata
    ])
    |> validate_required([:source_type, :endpoint_url, :poll_interval_seconds])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_number(:poll_interval_seconds, greater_than: 0)
    |> validate_number(:failure_count, greater_than_or_equal_to: 0)
    |> validate_length(:title, max: 1_000)
    |> validate_length(:etag, max: 4_096)
    |> validate_length(:last_modified, max: 4_096)
    |> validate_length(:last_error, max: 8_192)
    |> validate_endpoint_url()
    |> validate_bounded_metadata(:metadata)
    |> unique_constraint(:endpoint_url)
    |> check_constraint(:poll_interval_seconds,
      name: :poll_interval_seconds_must_be_positive
    )
    |> check_constraint(:failure_count, name: :failure_count_must_not_be_negative)
  end

  defp validate_endpoint_url(changeset) do
    validate_change(changeset, :endpoint_url, fn :endpoint_url, endpoint_url ->
      uri = URI.parse(endpoint_url)

      if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.userinfo == nil do
        []
      else
        [endpoint_url: "must be an absolute HTTP(S) URL without credentials"]
      end
    end)
  end

  defp validate_bounded_metadata(changeset, field) do
    validate_change(changeset, field, fn ^field, metadata ->
      cond do
        not is_map(metadata) ->
          [{field, "must be a map"}]

        Enum.any?(Map.keys(metadata), &(to_string(&1) in @sensitive_metadata_keys)) ->
          [{field, "must not contain credentials"}]

        byte_size(Jason.encode!(metadata)) > @metadata_limit_bytes ->
          [{field, "is too large"}]

        true ->
          []
      end
    end)
  end
end
