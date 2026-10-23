defmodule Lens.Investigations do
  @moduledoc "Registration and publication of manually authored investigation candidates."

  import Ecto.Query

  alias Lens.Investigations.Candidate
  alias Lens.Repo

  def register_candidate(attrs) do
    attrs |> Candidate.registration_changeset() |> Repo.insert()
  end

  def list_candidates do
    Repo.all(from(c in Candidate, order_by: [desc: c.published_at, desc: c.id]))
  end
end
