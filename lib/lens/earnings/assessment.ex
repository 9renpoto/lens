defmodule Lens.Earnings.Assessment do
  @moduledoc "An immutable automated assessment, separate from acquisition and operator decisions."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "earnings_assessments" do
    belongs_to(:http_check, Lens.Earnings.HTTPCheck)
    belongs_to(:target, Lens.Analysis.Target)
    belongs_to(:source, Lens.Earnings.Source)
    field(:outcome, :string)
    field(:document_kind, :string)
    field(:assessor, :string)
    field(:assessor_version, :string)
    field(:reason, :string)
    field(:identity, :map, default: %{})
    field(:evidence, :map)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(assessment, attrs) do
    assessment
    |> cast(attrs, ~w(outcome document_kind assessor assessor_version reason identity evidence)a)
    |> validate_required(~w(outcome assessor assessor_version reason identity evidence)a)
    |> validate_inclusion(:outcome, ~w(accepted excluded pending))
    |> validate_inclusion(:document_kind, ~w(earnings_release correction earnings_presentation))
    |> validate_length(:assessor, max: 100)
    |> validate_length(:assessor_version, max: 100)
    |> validate_length(:reason, max: 1000)
    |> validate_text(:assessor)
    |> validate_text(:assessor_version)
    |> validate_text(:reason)
    |> require_accepted_kind()
    |> canonical_json(:identity)
    |> canonical_json(:evidence)
    |> validate_change(:evidence, fn :evidence, value ->
      if value == %{}, do: [evidence: "must contain supporting evidence"], else: []
    end)
    |> foreign_key_constraint(:http_check_id)
    |> foreign_key_constraint(:target_id)
    |> foreign_key_constraint(:source_id)
    |> check_constraint(:outcome, name: :earnings_assessment_outcome)
    |> check_constraint(:document_kind, name: :earnings_assessment_kind)
    |> check_constraint(:evidence, name: :earnings_assessment_json)
    |> check_constraint(:reason, name: :earnings_assessment_text)
  end

  defp require_accepted_kind(changeset) do
    if get_field(changeset, :outcome) == "accepted",
      do: validate_required(changeset, [:document_kind]),
      else: changeset
  end

  defp canonical_json(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) ->
        with {:ok, json} <- Jason.encode(value),
             true <- byte_size(json) <= 65_536,
             {:ok, canonical} <- Jason.decode(json),
             true <- jsonb_safe?(canonical) do
          put_change(changeset, field, canonical)
        else
          _ ->
            add_error(
              changeset,
              field,
              "must be a JSON object without NUL characters within 65536 bytes"
            )
        end

      _ ->
        changeset
    end
  end

  defp validate_text(changeset, field) do
    validate_change(changeset, field, fn field, value ->
      if jsonb_safe?(value),
        do: [],
        else: [{field, "must be valid UTF-8 without NUL characters"}]
    end)
  end

  defp jsonb_safe?(value) when is_binary(value),
    do: String.valid?(value) and not String.contains?(value, <<0>>)

  defp jsonb_safe?(values) when is_list(values), do: Enum.all?(values, &jsonb_safe?/1)

  defp jsonb_safe?(values) when is_map(values),
    do: Enum.all?(values, fn {key, value} -> jsonb_safe?(key) and jsonb_safe?(value) end)

  defp jsonb_safe?(_), do: true
end
