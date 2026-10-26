defmodule Lens.Ingestion.Material do
  @moduledoc "An immutable successful material observation; HTML originals are not retained."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}

  schema "feed_materials" do
    belongs_to(:source, Lens.Content.Source)
    field(:item_key, :string)
    field(:feed_fingerprint, :string)
    field(:kind, :string)
    field(:requested_url, :string)
    field(:final_url, :string)
    field(:acquired_at, :utc_datetime_usec)
    field(:http_status, :integer)
    field(:requests, :integer)
    field(:byte_size, :integer)
    field(:content_hash, :string)
    field(:text, :string)
    belongs_to(:original, Lens.Earnings.Original)
    field(:source_snapshot, :map)
    field(:entry_snapshot, :map)
    field(:provenance, :map, default: %{})
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :source_id,
      :item_key,
      :feed_fingerprint,
      :kind,
      :requested_url,
      :final_url,
      :acquired_at,
      :http_status,
      :requests,
      :byte_size,
      :content_hash,
      :text,
      :original_id,
      :source_snapshot,
      :entry_snapshot,
      :provenance
    ])
    |> validate_required([
      :source_id,
      :item_key,
      :feed_fingerprint,
      :kind,
      :requested_url,
      :final_url,
      :acquired_at,
      :http_status,
      :requests,
      :byte_size,
      :content_hash,
      :source_snapshot,
      :entry_snapshot
    ])
    |> validate_inclusion(:kind, ~w(html pdf))
    |> validate_format(:content_hash, ~r/\A[0-9a-f]{64}\z/)
    |> validate_length(:requested_url, max: 8192)
    |> validate_length(:final_url, max: 8192)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:original_id)
    |> check_constraint(:kind, name: :feed_materials_payload)
  end
end
