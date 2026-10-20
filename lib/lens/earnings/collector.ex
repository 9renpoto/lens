defmodule Lens.Earnings.Collector do
  @moduledoc "Bounded acquisition of registered listing candidates, independent of assessment."
  alias Lens.Earnings.{
    Discovery,
    HTTPCheck,
    HTTPHistory,
    RunBudget,
    RustFS,
    SourceCatalog
  }

  def run(options \\ []) do
    with {:ok, budget} <- RunBudget.new(options),
         {:ok, client} <- storage_client(options) do
      state = %{budget: budget, checks: [], errors: [], stopped: nil}
      policy = Keyword.get(options, :allowed_url?, &HTTPCheck.valid_url?/1)

      state =
        Enum.reduce_while(SourceCatalog.all(enabled_only: true), state, fn source, state ->
          state = collect(source, state, policy, client)

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

        remaining_operations = state.budget.max_operations - state.budget.operations

        case discover(result, remaining_operations) do
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

          {:error, :operation_budget_exhausted} ->
            %{state | stopped: :operation_budget_exhausted}

          {:error, reason} ->
            %{state | errors: [%{source_id: source.id, reason: reason} | state.errors]}
        end

      {:ok, _, state} ->
        state

      {:error, state} ->
        state
    end
  end

  defp discover(_, remaining_operations) when remaining_operations <= 0,
    do: {:error, :operation_budget_exhausted}

  defp discover(result, remaining_operations),
    do: Discovery.links(result.final_url, result.bytes, max_links: remaining_operations)

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
                 stopped: :storage_failed,
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
    remaining = budget.deadline - System.monotonic_time(:millisecond)

    if remaining < 2 do
      case HTTPHistory.fail_storage(attrs, :run_deadline_exceeded) do
        {:storage_failed, _} -> {:deferred, :run_deadline_exceeded}
        {:error, _} = error -> error
      end
    else
      # Conditional creation and byte verification share the remaining run deadline.
      client = %{client | timeout_ms: min(client.timeout_ms, div(remaining, 2))}
      HTTPHistory.store(attrs, client)
    end
  end

  defp persist(attrs, _, _), do: HTTPHistory.record(attrs)
end
