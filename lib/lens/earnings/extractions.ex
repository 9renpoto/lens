defmodule Lens.Earnings.Extractions do
  @moduledoc "Extraction attempts derived from immutable retained originals."
  import Ecto.Query
  alias Lens.Earnings.{Acquisition, Extraction, Release}
  alias Lens.Repo

  def begin(original_id, extractor, version) do
    original_id |> Extraction.pending(extractor, version) |> Repo.insert()
  end

  def latest_success(original_id) do
    Repo.one(
      from(e in Extraction,
        where: e.original_id == ^original_id and e.status == "succeeded",
        order_by: [desc: e.id],
        limit: 1
      )
    )
  end

  @doc "Select release text in one database snapshot, ordered by first acquisition of each original."
  def release_text(release_id) do
    eligible =
      from(a in Acquisition,
        where: a.release_id == ^release_id and a.status == "success",
        group_by: a.original_id,
        select: %{original_id: a.original_id, first_at: min(a.acquired_at)}
      )

    latest =
      from(o in subquery(eligible),
        order_by: [desc: o.first_at, desc: o.original_id],
        limit: 1
      )

    selected =
      from(e in Extraction,
        join: o in subquery(eligible),
        on: e.original_id == o.original_id,
        where: e.status == "succeeded",
        order_by: [desc: o.first_at, desc: o.original_id, desc: e.id],
        limit: 1,
        select: e,
        select_merge: %{
          search_mode:
            fragment("CASE WHEN ?.search_vector IS NULL THEN 'substring' ELSE 'full_text' END", e)
        }
      )

    latest_attempt =
      from(e in Extraction,
        join: o in subquery(latest),
        on: e.original_id == o.original_id,
        order_by: [desc: e.id],
        limit: 1,
        select: e,
        select_merge: %{
          search_mode:
            fragment(
              "CASE WHEN ? <> 'succeeded' THEN 'none' WHEN ?.search_vector IS NULL THEN 'substring' ELSE 'full_text' END",
              e.status,
              e
            )
        }
      )

    result =
      Repo.one(
        from(r in Release,
          where: r.id == ^release_id,
          left_join: l in subquery(latest),
          on: true,
          left_join: e in subquery(selected),
          on: true,
          left_join: a in subquery(latest_attempt),
          on: true,
          select: %{extraction: e, latest_original_id: l.original_id, latest_attempt: a}
        )
      )

    case result do
      nil ->
        {:error, :not_found}

      %{extraction: extraction, latest_original_id: latest_id} ->
        {:ok,
         Map.put(result, :stale, not is_nil(extraction) and extraction.original_id != latest_id)}
    end
  end

  def succeed(id, text, metadata \\ [])

  def succeed(id, text, metadata) when is_binary(text) do
    if valid_text?(text) do
      finish(
        id,
        Keyword.merge(metadata,
          status: "succeeded",
          text: text,
          search_text: Lens.Search.Normalizer.document_text(nil, text)
        )
      )
    else
      {:error, :invalid_text}
    end
  end

  def succeed(_, _, _), do: {:error, :invalid_text}

  def fail(id, reason, metadata \\ [])

  def fail(id, reason, metadata) when is_binary(reason) do
    if valid_text?(reason),
      do: finish(id, Keyword.merge(metadata, status: "failed", failure_reason: reason)),
      else: {:error, :invalid_reason}
  end

  def fail(_, _, _), do: {:error, :invalid_reason}

  defp valid_text?(text) do
    String.valid?(text) and not String.contains?(text, <<0>>) and String.trim(text) != ""
  end

  defp finish(id, fields) do
    fields =
      fields
      |> Keyword.take([:status, :text, :search_text, :failure_reason, :extractor_version])
      |> Keyword.put(:finished_at, DateTime.utc_now())

    query = from(e in Extraction, where: e.id == ^id and e.status == "pending", select: e)

    case Repo.update_all(query, set: fields) do
      {1, [extraction]} -> {:ok, extraction}
      {0, []} -> {:error, :not_pending}
    end
  end
end
