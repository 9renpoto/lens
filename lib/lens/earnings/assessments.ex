defmodule Lens.Earnings.Assessments do
  @moduledoc "Shared append-only outcome and evidence recording for collected document candidates."
  import Ecto.Query
  alias Lens.Earnings.{Acquisition, Assessment, HTTPCheck, Source}
  alias Lens.Repo

  @doc "Append one assessment of a successful registered-source PDF HTTP check."
  def record(candidate_id, attrs) when is_map(attrs) do
    with {:ok, id} <- Ecto.UUID.cast(candidate_id),
         %HTTPCheck{} = check <- Repo.get(HTTPCheck, id),
         %{} = provenance <- candidate_provenance(check) do
      struct(Assessment, provenance)
      |> Assessment.changeset(attrs)
      |> Repo.insert()
    else
      nil -> {:error, :not_found}
      _ -> {:error, :invalid_candidate}
    end
  end

  def record(_, _), do: {:error, :invalid_assessment}

  @doc "Read at most 100 assessment records for a candidate, newest first."
  def history(candidate_id, limit \\ 100)

  def history(candidate_id, limit) when is_integer(limit) and limit in 1..100 do
    case Ecto.UUID.cast(candidate_id) do
      {:ok, id} ->
        Repo.all(
          from(a in Assessment,
            where: a.http_check_id == ^id,
            order_by: [desc: a.inserted_at, desc: a.id],
            limit: ^limit
          )
        )

      _ ->
        []
    end
  end

  def history(_, _), do: {:error, :invalid_limit}

  defp candidate_provenance(%{kind: "pdf", status: "success"} = check) do
    Repo.one(
      from(s in Source,
        join: a in Acquisition,
        on: a.id == ^check.acquisition_id,
        where:
          fragment("?::text = ?", s.id, ^check.metadata["source_id"]) and
            fragment("?::text = ?", s.target_id, ^check.metadata["target_id"]) and
            a.status == "success" and not is_nil(a.original_id) and
            a.issuer_code == ^check.issuer_code,
        select: %{http_check_id: ^check.id, target_id: s.target_id, source_id: s.id}
      )
    ) || :invalid_candidate
  end

  defp candidate_provenance(_), do: :invalid_candidate
end
