defmodule Lens.Earnings.Collector do
  @moduledoc "Bounded acquisition of registered listing candidates, independent of assessment."
  alias Lens.Earnings.{Discovery, HTTPCheck, HTTPHistory, RunBudget, SourceCatalog}

  def run(options \\ []) do
    with {:ok, budget} <- RunBudget.new(options) do
      state = %{budget: budget, checks: [], errors: [], stopped: nil}
      policy = Keyword.get(options, :allowed_url?, &HTTPCheck.valid_url?/1)

      state =
        Enum.reduce_while(SourceCatalog.all(enabled_only: true), state, fn source, state ->
          state = collect(source, state, policy)
          if state.stopped, do: {:halt, state}, else: {:cont, state}
        end)

      {:ok, %{state | checks: Enum.reverse(state.checks), errors: Enum.reverse(state.errors)}}
    end
  end

  defp collect(source, state, policy) do
    metadata = Map.take(source, [:target_id, :listing_url]) |> Map.put(:source_id, source.id)

    case fetch(source, source.listing_url, :listing, metadata, state, policy) do
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

              case fetch(source, link.url, :pdf, metadata, state, policy) do
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

  defp fetch(source, url, kind, metadata, state, policy) do
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

        case HTTPHistory.record(attrs) do
          {:ok, check} ->
            {:ok, result, %{state | budget: budget, checks: [check | state.checks]}}

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
end
