defmodule Lens.Analysis.Target do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "An operator-managed analysis target / security."
  @type t :: %__MODULE__{
          id: binary() | nil,
          security_code: String.t() | nil,
          market: String.t() | nil,
          display_name: String.t() | nil,
          sector: String.t() | nil,
          tags: list(String.t()),
          active: boolean(),
          source_reference: String.t() | nil,
          verified_at: DateTime.t() | nil
        }

  schema "analysis_targets" do
    field(:security_code, :string)
    field(:market, :string)
    field(:display_name, :string)
    field(:sector, :string)
    field(:tags, {:array, :string}, default: [])
    field(:active, :boolean, default: true)
    field(:source_reference, :string)
    field(:verified_at, :utc_datetime_usec)

    has_many(:memberships, Lens.Analysis.Membership, foreign_key: :target_id)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(target, attrs) do
    target
    |> cast(attrs, [
      :security_code,
      :market,
      :display_name,
      :sector,
      :tags,
      :active,
      :source_reference,
      :verified_at
    ])
    |> validate_required([:security_code, :market, :display_name, :sector])
    |> validate_length(:security_code, min: 1, max: 50)
    |> validate_length(:market, max: 100)
    |> validate_length(:display_name, max: 255)
    |> validate_length(:sector, max: 100)
    |> validate_length(:source_reference, max: 1000)
    |> validate_tags()
    |> unique_constraint(:security_code)
  end

  defp validate_tags(changeset) do
    validate_change(changeset, :tags, fn :tags, tags ->
      cond do
        not is_list(tags) ->
          [tags: "must be a list"]

        length(tags) > 10 ->
          [tags: "should have at most 10 item(s)"]

        Enum.any?(tags, &(not is_binary(&1) or String.length(&1) > 50)) ->
          [tags: "contains invalid tag elements"]

        true ->
          []
      end
    end)
  end
end
