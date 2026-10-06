defmodule Lens.Earnings.Sources do
  @moduledoc "Database-managed listing sources associated with existing analysis targets."

  import Ecto.Query
  alias Lens.Analysis.Target
  alias Lens.Earnings.Source
  alias Lens.Repo

  def list(target_id) do
    Repo.all(
      from(s in Source,
        where: s.target_id == ^target_id,
        order_by: [asc: s.inserted_at, asc: s.id]
      )
    )
  end

  def fetch(target_id, id) do
    with {:ok, target_uuid} <- Ecto.UUID.cast(target_id),
         {:ok, source_uuid} <- Ecto.UUID.cast(id),
         %Source{} = source <- Repo.get_by(Source, target_id: target_uuid, id: source_uuid) do
      {:ok, source}
    else
      _ -> :error
    end
  end

  def create(%Target{id: target_id}, attrs) do
    %Source{target_id: target_id} |> Source.changeset(attrs) |> Repo.insert()
  end

  def update(%Source{} = source, attrs) do
    source |> Source.changeset(attrs) |> Repo.update()
  end
end
