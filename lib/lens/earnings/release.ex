defmodule Lens.Earnings.Release do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "earnings_releases" do
    field(:issuer_code, :string)
    field(:fiscal_year_end, :date)
    field(:period, :string)
    field(:category, :string)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(release, attrs) do
    release
    |> cast(attrs, [:issuer_code, :fiscal_year_end, :period, :category])
    |> validate_required([:issuer_code, :fiscal_year_end, :period, :category])
    |> validate_format(:issuer_code, ~r/^\d{4}$/)
    |> validate_inclusion(:period, ~w(q1 q2 q3 full_year))
    |> validate_length(:category, min: 1, max: 100)
    |> unique_constraint([:issuer_code, :fiscal_year_end, :period, :category])
  end
end
