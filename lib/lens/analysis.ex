defmodule Lens.Analysis do
  @moduledoc """
  The Analysis context for operator-managed target securities and index membership intervals over time.
  """

  import Ecto.Query

  alias Lens.Analysis.{Membership, Target}
  alias Lens.Repo

  @doc """
  Lists analysis targets.

  Options:
    * `:as_of` - Date or ISO8601 string date. When provided, returns only targets that have
      an active membership interval on that date and have active == true.
  """
  def list_targets(opts \\ []) do
    as_of = parse_as_of_date(Keyword.get(opts, :as_of))

    query = from(t in Target, order_by: [asc: t.security_code])

    query =
      if as_of do
        from(t in query,
          join: m in Membership,
          on: m.target_id == t.id,
          where:
            t.active == true and
              m.effective_from <= ^as_of and
              (is_nil(m.effective_to) or m.effective_to >= ^as_of),
          distinct: t.id
        )
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(memberships: from(m in Membership, order_by: [asc: m.effective_from]))
  end

  @doc """
  Fetches a single target by ID with preloaded memberships.
  """
  def fetch_target(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Repo.get(Target, uuid) do
          nil ->
            :error

          target ->
            {:ok,
             Repo.preload(target,
               memberships: from(m in Membership, order_by: [asc: m.effective_from])
             )}
        end

      :error ->
        :error
    end
  end

  @doc """
  Gets a single target by ID with preloaded memberships.
  Raises Ecto.NoResultsError if not found.
  """
  def get_target!(id) do
    Target
    |> Repo.get!(id)
    |> Repo.preload(memberships: from(m in Membership, order_by: [asc: m.effective_from]))
  end

  @doc """
  Creates a target.
  """
  def create_target(attrs) do
    %Target{}
    |> Target.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a target.
  """
  def update_target(%Target{} = target, attrs) do
    target
    |> Target.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deactivates a target non-destructively.
  """
  def deactivate_target(%Target{} = target) do
    update_target(target, %{active: false})
  end

  @doc """
  Lists membership intervals for a target.
  """
  def list_memberships(target_id) do
    from(m in Membership,
      where: m.target_id == ^target_id,
      order_by: [asc: m.effective_from]
    )
    |> Repo.all()
  end

  @doc """
  Creates a membership interval for a target.
  """
  def create_membership(%Target{} = target, attrs) when is_map(attrs) do
    key = if Enum.any?(Map.keys(attrs), &is_binary/1), do: "target_id", else: :target_id
    attrs = Map.put(attrs, key, target.id)
    create_membership(attrs)
  end

  def create_membership(attrs) when is_map(attrs) do
    %Membership{}
    |> Membership.changeset(attrs)
    |> Membership.validate_no_overlapping_intervals(Repo)
    |> Repo.insert()
  end

  defp parse_as_of_date(%Date{} = date), do: date

  defp parse_as_of_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} ->
        date

      _ ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _offset} -> DateTime.to_date(dt)
          _ -> nil
        end
    end
  end

  defp parse_as_of_date(_), do: nil
end
