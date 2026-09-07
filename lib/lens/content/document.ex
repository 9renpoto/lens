defmodule Lens.Content.Document do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Canonical normalized content, independent of the source that observed it."
  @type t :: %__MODULE__{
          id: binary() | nil,
          identity_key: String.t() | nil,
          canonical_url: String.t() | nil,
          content: String.t() | nil,
          content_hash: String.t() | nil
        }

  schema "documents" do
    field(:identity_key, :string)
    field(:canonical_url, :string)
    field(:title, :string)
    field(:content, :string)
    field(:author, :string)
    field(:published_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})
    field(:content_hash, :string)

    has_many(:observations, Lens.Content.Observation)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :identity_key,
      :canonical_url,
      :title,
      :content,
      :author,
      :published_at,
      :metadata,
      :content_hash
    ])
    |> validate_required([:identity_key, :content, :content_hash])
    |> validate_length(:identity_key, max: 4_096)
    |> validate_length(:content_hash, is: 64)
    |> validate_change(:canonical_url, &validate_canonical_url/2)
    |> validate_map()
    |> unique_constraint(:identity_key)
    |> unique_constraint(:canonical_url)
  end

  defp validate_canonical_url(:canonical_url, canonical_url) do
    uri = URI.parse(canonical_url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.userinfo == nil do
      []
    else
      [canonical_url: "must be an absolute HTTP(S) URL without credentials"]
    end
  end

  defp validate_map(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      if is_map(metadata), do: [], else: [metadata: "must be a map"]
    end)
  end
end
