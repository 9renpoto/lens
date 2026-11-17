defmodule Lens.Analysis do
  @moduledoc """
  The Analysis context for operator-managed target securities.
  """

  import Ecto.Query

  alias Lens.Analysis.Target
  alias Lens.Repo

  @doc """
  Lists analysis targets ordered by security code.
  """
  def list_targets do
    Repo.all(from(t in Target, order_by: [asc: t.security_code]))
  end

  @doc """
  Fetches a single target by ID.
  """
  def fetch_target(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Target{} = target <- Repo.get(Target, uuid) do
      {:ok, target}
    else
      _ -> :error
    end
  end

  @doc """
  Gets a single target by ID.
  Raises Ecto.NoResultsError if not found.
  """
  def get_target!(id), do: Repo.get!(Target, id)

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
end
