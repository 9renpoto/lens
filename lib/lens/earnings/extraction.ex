defmodule Lens.Earnings.Extraction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "earnings_extractions" do
    field(:original_id, Ecto.UUID)
    field(:extractor, :string)
    field(:extractor_version, :string)
    field(:status, :string)
    field(:extraction_options, :map, default: %{})
    field(:text, :string)
    field(:search_text, :string, default: "")
    field(:search_mode, :string, virtual: true)
    field(:failure_reason, :string)
    field(:finished_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def pending(original_id, extractor, version, options \\ %{}) do
    %__MODULE__{}
    |> cast(
      %{
        original_id: original_id,
        extractor: extractor,
        extractor_version: version,
        status: "pending",
        extraction_options: options
      },
      [:original_id, :extractor, :extractor_version, :status, :extraction_options]
    )
    |> validate_required([:original_id, :extractor, :extractor_version, :status])
    |> foreign_key_constraint(:original_id)
  end
end
