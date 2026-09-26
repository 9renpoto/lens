defmodule Lens.Earnings.Acquisition do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "earnings_acquisitions" do
    field(:acquisition_id, :string)
    field(:issuer_code, :string)
    field(:url, :string)
    field(:acquired_at, :utc_datetime_usec)
    field(:status, :string)
    field(:failure_reason, :string)
    belongs_to(:original, Lens.Earnings.Original)
    belongs_to(:release, Lens.Earnings.Release)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(acquisition, attrs) do
    acquisition
    |> provenance_changeset(attrs)
    |> cast(attrs, [
      :status,
      :failure_reason,
      :original_id,
      :release_id
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, ~w(success failed))
    |> validate_status()
    |> unique_constraint(:acquisition_id)
    |> foreign_key_constraint(:original_id)
    |> foreign_key_constraint(:release_id)
  end

  def provenance_changeset(acquisition, attrs) do
    acquisition
    |> cast(attrs, [:acquisition_id, :issuer_code, :url, :acquired_at])
    |> validate_required([:acquisition_id, :issuer_code, :url, :acquired_at])
    |> validate_length(:acquisition_id, min: 1, max: 200)
    |> validate_format(:issuer_code, ~r/^\d{4}$/)
    |> validate_length(:url, max: 4096)
    |> validate_url()
  end

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, value ->
      uri = URI.parse(value)

      if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.userinfo == nil,
        do: [],
        else: [url: "must be an absolute HTTP(S) URL without credentials"]
    end)
  end

  defp validate_status(changeset) do
    status = get_field(changeset, :status)
    original_id = get_field(changeset, :original_id)
    release_id = get_field(changeset, :release_id)
    reason = get_field(changeset, :failure_reason)

    cond do
      status == "success" and (is_nil(original_id) or not is_nil(reason)) ->
        add_error(changeset, :status, "requires an original and no failure reason")

      status == "failed" and (not is_nil(original_id) or not is_nil(release_id) or is_nil(reason)) ->
        add_error(changeset, :status, "requires a reason and no original or release")

      true ->
        changeset
    end
  end
end
