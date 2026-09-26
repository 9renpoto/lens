defmodule Lens.Analysis.Membership do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "An effective-dated index membership interval."
  @type t :: %__MODULE__{
          id: binary() | nil,
          target_id: binary() | nil,
          index_name: String.t(),
          effective_from: Date.t() | nil,
          effective_to: Date.t() | nil,
          source_reference: String.t() | nil,
          verified_at: DateTime.t() | nil
        }

  schema "analysis_memberships" do
    field(:index_name, :string, default: "nikkei_225")
    field(:effective_from, :date)
    field(:effective_to, :date)
    field(:source_reference, :string)
    field(:verified_at, :utc_datetime_usec)

    belongs_to(:target, Lens.Analysis.Target, type: :binary_id)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :target_id,
      :index_name,
      :effective_from,
      :effective_to,
      :source_reference,
      :verified_at
    ])
    |> validate_explicit_index_name(attrs)
    |> validate_explicit_effective_to(attrs)
    |> validate_explicit_verified_at(attrs)
    |> validate_required([:target_id, :index_name, :effective_from])
    |> validate_length(:index_name, min: 1, max: 100, count: :codepoints)
    |> validate_length(:source_reference, max: 1000, count: :codepoints)
    |> validate_effective_dates()
    |> validate_database_constraints()
  end

  def update_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:effective_to, :source_reference, :verified_at])
    |> validate_explicit_effective_to(attrs)
    |> validate_explicit_verified_at(attrs)
    |> validate_length(:source_reference, max: 1000, count: :codepoints)
    |> validate_effective_dates()
    |> validate_database_constraints()
  end

  defp validate_explicit_index_name(changeset, attrs) when is_map(attrs) do
    index_name = Map.get(attrs, :index_name, Map.get(attrs, "index_name"))

    if is_binary(index_name) and String.trim(index_name) == "" do
      add_error(changeset, :index_name, "can't be blank")
    else
      changeset
    end
  end

  defp validate_explicit_index_name(changeset, _attrs), do: changeset

  defp validate_explicit_effective_to(changeset, attrs) when is_map(attrs) do
    effective_to = Map.get(attrs, :effective_to, Map.get(attrs, "effective_to"))

    if is_binary(effective_to) and String.trim(effective_to) == "" do
      add_error(changeset, :effective_to, "is invalid")
    else
      changeset
    end
  end

  defp validate_explicit_effective_to(changeset, _attrs), do: changeset

  defp validate_explicit_verified_at(changeset, attrs) when is_map(attrs) do
    verified_at = Map.get(attrs, :verified_at, Map.get(attrs, "verified_at"))

    if is_binary(verified_at) and String.trim(verified_at) == "" do
      add_error(changeset, :verified_at, "is invalid")
    else
      changeset
    end
  end

  defp validate_explicit_verified_at(changeset, _attrs), do: changeset

  defp validate_database_constraints(changeset) do
    changeset
    |> check_constraint(:effective_to,
      name: :effective_to_must_be_on_or_after_effective_from
    )
    |> exclusion_constraint(:effective_from,
      name: :analysis_memberships_no_overlapping_intervals,
      message: "overlaps with an existing membership interval"
    )
  end

  def validate_no_overlapping_intervals(changeset, repo \\ Lens.Repo) do
    target_id = get_field(changeset, :target_id)
    index_name = get_field(changeset, :index_name) || "nikkei_225"
    effective_from = get_field(changeset, :effective_from)
    effective_to = get_field(changeset, :effective_to)
    id = get_field(changeset, :id)

    if changeset.valid? && not is_nil(target_id) && not is_nil(effective_from) do
      query =
        from(m in __MODULE__,
          where: m.target_id == ^target_id,
          where: m.index_name == ^index_name
        )

      query = if id, do: from(m in query, where: m.id != ^id), else: query

      query =
        if effective_to do
          from(m in query, where: m.effective_from <= ^effective_to)
        else
          query
        end

      overlapping_query =
        from(m in query,
          where: is_nil(m.effective_to) or m.effective_to >= ^effective_from
        )

      if repo.exists?(overlapping_query) do
        add_error(
          changeset,
          :effective_from,
          "overlaps with an existing membership interval"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_effective_dates(changeset) do
    effective_from = get_field(changeset, :effective_from)
    effective_to = get_field(changeset, :effective_to)

    if effective_from && effective_to && Date.compare(effective_to, effective_from) == :lt do
      add_error(changeset, :effective_to, "must be on or after effective_from")
    else
      changeset
    end
  end
end
