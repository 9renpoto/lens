defmodule Lens.Earnings.HTTPHistory do
  @moduledoc "Atomic persistence of immutable HTTP checks and actual PDF acquisition outcomes."
  alias Lens.Earnings
  alias Lens.Earnings.HTTPCheck
  alias Lens.Earnings.HTTPResponseFacts, as: ResponseFacts
  alias Lens.Repo

  def record(%{result: result} = attrs) when is_map(result) do
    Repo.transaction(fn ->
      with {:ok, check} <- prepare(attrs, result),
           {:ok, acquisition} <- acquisition(check, attrs, result),
           {:ok, stored} <- insert(%{check | acquisition_id: acquisition && acquisition.id}) do
        stored
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def record(_), do: {:error, :invalid_result}

  @doc "Validate and retain a collected PDF observation before any object I/O."
  def prepare_storage(%{result: result} = attrs, client) do
    with {:ok, %{kind: "pdf", status: "success"} = check} <- prepare(attrs, result),
         {:ok, source_id} <- Ecto.UUID.cast(check.metadata["source_id"]) do
      input =
        common(check, check.final_url)
        |> Map.merge(%{
          bytes: result.bytes,
          release: Map.get(attrs, :release),
          source_id: source_id,
          http_check: Map.take(check, HTTPCheck.facts()) |> Jason.encode!() |> Jason.decode!()
        })

      Lens.Earnings.StorageWork.prepare(input, client)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_result}
    end
  end

  @doc "Insert retained HTTP facts with the verified acquisition inside the completion transaction."
  def complete_storage(nil, _), do: :ok

  def complete_storage(facts, acquisition_id) do
    changeset =
      HTTPCheck.changeset(%HTTPCheck{}, Map.put(facts, "acquisition_id", acquisition_id))

    with {:ok, check} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, _} <- insert(check) do
      :ok
    end
  end

  defp prepare(attrs, result) do
    kind = Map.get(attrs, :kind, :pdf)
    bytes = Map.get(result, :bytes)
    status = stringify(Map.get(result, :outcome))

    cond do
      status == "success" and not is_binary(bytes) ->
        {:error, :invalid_result}

      status != "success" and bytes != nil ->
        {:error, :invalid_result}

      status == "success" and stringify(kind) == "pdf" and not String.starts_with?(bytes, "%PDF-") ->
        {:error, :invalid_result}

      true ->
        final_url = Map.get(result, :final_url)

        facts =
          attrs
          |> Map.take([:check_id, :issuer_code, :url, :checked_at, :published_on, :metadata])
          |> Map.merge(%{
            kind: stringify(kind),
            status: status,
            final_url: final_url,
            failure_reason: stringify(Map.get(result, :failure_reason)),
            http_status: Map.get(result, :http_status),
            requests: Map.get(result, :requests),
            retryable: Map.get(result, :retryable),
            response_headers: ResponseFacts.normalize_headers(Map.get(result, :headers, %{})),
            byte_size: if(is_binary(bytes), do: byte_size(bytes)),
            sha256:
              if(is_binary(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower))
          })

        changeset = HTTPCheck.changeset(%HTTPCheck{}, facts)

        if changeset.valid?,
          do: {:ok, changeset |> Ecto.Changeset.apply_changes() |> canonical_json()},
          else: {:error, changeset}
    end
  end

  defp canonical_json(check) do
    Enum.reduce([:metadata, :response_headers], check, fn field, acc ->
      Map.update!(acc, field, fn value -> value |> Jason.encode!() |> Jason.decode!() end)
    end)
  end

  defp acquisition(%{kind: "pdf", status: "success"} = check, attrs, result) do
    input =
      common(check, check.final_url)
      |> Map.put(:bytes, result.bytes)
      |> Map.put(:release, Map.get(attrs, :release))

    case Earnings.record_success(input) do
      {:ok, %{acquisition: acquisition}} -> {:ok, acquisition}
      {:error, reason} -> {:error, reason}
    end
  end

  defp acquisition(%{kind: "pdf", status: "failed", requests: requests} = check, _, _)
       when requests > 0,
       do:
         Earnings.record_failure(Map.put(common(check, check.url), :reason, check.failure_reason))

  defp acquisition(_, _, _), do: {:ok, nil}

  defp common(check, url),
    do: %{
      acquisition_id: "http:" <> check.check_id,
      issuer_code: check.issuer_code,
      url: url,
      acquired_at: check.checked_at
    }

  defp insert(check) do
    attrs = Map.take(check, HTTPCheck.facts())

    case Repo.insert(HTTPCheck.changeset(%HTTPCheck{}, attrs),
           on_conflict: :nothing,
           conflict_target: :check_id
         ) do
      {:ok, _} ->
        stored = Repo.get_by!(HTTPCheck, check_id: check.check_id)

        if Map.take(stored, HTTPCheck.facts()) == attrs,
          do: {:ok, stored},
          else: {:error, :check_conflict}

      error ->
        error
    end
  end

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value
end
