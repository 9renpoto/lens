defmodule Lens.Earnings.Collector do
  @moduledoc "Bounded acquisition of registered listing candidates, independent of assessment."
  alias Lens.Earnings.{
    Discovery,
    HTTPCheck,
    HTTPHistory,
    RunBudget,
    RustFS,
    SourceCatalog,
    StorageWork
  }

  def run(options \\ []) do
    with {:ok, budget} <- RunBudget.new(options),
         {:ok, client} <- storage_client(options) do
      state = %{budget: budget, checks: [], errors: [], stopped: nil}
      policy = Keyword.get(options, :allowed_url?, &HTTPCheck.valid_url?/1)

      state =
        Enum.reduce_while(SourceCatalog.all(enabled_only: true), state, fn source, state ->
          state =
            if StorageWork.unfinished_for_source?(source.id),
              do: state,
              else: collect(source, state, policy, client)

          if state.stopped, do: {:halt, state}, else: {:cont, state}
        end)

      {:ok, %{state | checks: Enum.reverse(state.checks), errors: Enum.reverse(state.errors)}}
    end
  end

  defp collect(source, state, policy, client) do
    metadata = Map.take(source, [:target_id, :listing_url]) |> Map.put(:source_id, source.id)

    case fetch(source, source.listing_url, :listing, metadata, state, policy, client) do
      {:ok, %{outcome: :success} = result, state} ->
        metadata =
          Map.merge(metadata, %{
            listing_check_id: hd(state.checks).id,
            observed_listing_url: result.final_url
          })

        case Discovery.links(result.final_url, result.bytes) do
          {:ok, links} ->
            Enum.reduce_while(links, state, fn link, state ->
              link =
                Map.update!(link, :headings, fn headings ->
                  Enum.map(headings, fn {level, text} -> %{level: level, text: text} end)
                end)

              metadata = Map.merge(Map.drop(link, [:comparison_url]), metadata)

              case fetch(source, link.url, :pdf, metadata, state, policy, client) do
                {:ok, _, state} -> {:cont, state}
                {:error, state} -> {:halt, state}
              end
            end)

          {:error, reason} ->
            %{state | errors: [%{source_id: source.id, reason: reason} | state.errors]}
        end

      {:ok, _, state} ->
        state

      {:error, state} ->
        state
    end
  end

  defp fetch(source, url, kind, metadata, state, policy, client) do
    case RunBudget.fetch(state.budget, url, kind: kind, allowed_url?: policy) do
      {:ok, result, budget} ->
        attrs = %{
          check_id: Ecto.UUID.generate(),
          issuer_code: source.issuer_code,
          url: url,
          kind: kind,
          checked_at: DateTime.utc_now(),
          metadata: metadata,
          result: result
        }

        case persist(attrs, client, budget) do
          {:ok, check} ->
            {:ok, result, %{state | budget: budget, checks: [check | state.checks]}}

          {:storage_failed, reason} ->
            {:error,
             %{
               state
               | budget: budget,
                 errors: [
                   %{source_id: source.id, reason: {:storage_failed, reason}} | state.errors
                 ]
             }}

          {:deferred, reason} ->
            {:error, %{state | budget: budget, stopped: reason}}

          {:error, reason} ->
            {:error,
             %{
               state
               | budget: budget,
                 stopped: :persistence_failed,
                 errors: [%{source_id: source.id, reason: reason} | state.errors]
             }}
        end

      {:error, reason, budget} ->
        {:error, %{state | budget: budget, stopped: reason}}
    end
  end

  defp storage_client(options) do
    case Keyword.fetch(options, :rustfs) do
      {:ok, %RustFS{} = client} -> {:ok, client}
      {:ok, _} -> {:error, :invalid_configuration}
      :error -> RustFS.new()
    end
  end

  defp persist(%{kind: :pdf, result: %{outcome: :success}} = attrs, client, budget) do
    with {:ok, work} <- HTTPHistory.prepare_storage(attrs, client) do
      remaining = budget.deadline - System.monotonic_time(:millisecond)

      if remaining < 3 do
        {:deferred, :run_deadline_exceeded}
      else
        # Recovery makes at most three requests; retain the shared run deadline.
        client = %{client | timeout_ms: min(client.timeout_ms, div(remaining, 3))}

        case StorageWork.recover(work.id, client) do
          {:ok, %{status: "completed"}} ->
            {:ok, Lens.Repo.get_by!(HTTPCheck, check_id: attrs.check_id)}

          {:ok, work} ->
            {:storage_failed, work.last_failure}

          {:error, :not_eligible} ->
            case Lens.Repo.get!(StorageWork, work.id) do
              %{status: "completed"} ->
                {:ok, Lens.Repo.get_by!(HTTPCheck, check_id: attrs.check_id)}

              _ ->
                {:storage_failed, "not_eligible"}
            end

          {:error, reason} when reason in [:stale_claim, :destination_mismatch] ->
            {:storage_failed, Atom.to_string(reason)}

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      {:error, :source_busy} -> {:storage_failed, "source_busy"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist(attrs, _, _), do: HTTPHistory.record(attrs)
end
