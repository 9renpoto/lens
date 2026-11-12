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
      http = [allowed_url?: Keyword.get(options, :allowed_url?, &HTTPCheck.valid_url?/1)]

      state =
        Enum.reduce_while(SourceCatalog.all(enabled_only: true), new_run(budget), fn source,
                                                                                     state ->
          state = collect(source, state, http, client, :prefix)

          if state.stopped, do: {:halt, state}, else: {:cont, state}
        end)

      finish(state)
    end
  end

  @doc "Acquire one exact PDF URL from a single enabled registered source."
  def run_selected(source_id, pdf_url, options \\ []) do
    with {:ok, source} <- enabled_source(source_id),
         true <- HTTPCheck.valid_url?(pdf_url),
         {:ok, budget} <- RunBudget.new(options),
         {:ok, client} <- storage_client(options) do
      http = [
        allowed_url?: Keyword.get(options, :allowed_url?, &HTTPCheck.valid_url?/1),
        max_redirects: 0
      ]

      source
      |> collect(new_run(budget), http, client, {:selected, pdf_url})
      |> finish()
    else
      false -> {:error, :invalid_selected_pdf_url}
      {:error, _} = error -> error
    end
  end

  defp enabled_source(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         [source] <- SourceCatalog.all(enabled_only: true, source_id: id) do
      {:ok, source}
    else
      _ -> {:error, :enabled_source_not_found}
    end
  end

  defp new_run(budget), do: %{budget: budget, checks: [], errors: [], stopped: nil}

  defp finish(state),
    do: {:ok, %{state | checks: Enum.reverse(state.checks), errors: Enum.reverse(state.errors)}}

  defp collect(source, state, http, client, mode) do
    metadata = Map.take(source, [:target_id, :listing_url]) |> Map.put(:source_id, source.id)

    case fetch(source, source.listing_url, :listing, metadata, state, http, client) do
      {:ok, %{outcome: :success} = result, state} ->
        metadata =
          Map.merge(metadata, %{
            listing_check_id: hd(state.checks).id,
            observed_listing_url: result.final_url
          })

        remaining_operations = state.budget.max_operations - state.budget.operations

        case discover(result, remaining_operations, mode) do
          {:ok, links} ->
            collect_links(links, source, metadata, state, http, client, mode)

          {:error, :operation_budget_exhausted} ->
            %{state | stopped: :operation_budget_exhausted}

          {:error, reason} ->
            state = %{state | errors: [%{source_id: source.id, reason: reason} | state.errors]}
            stop_selected(state, mode, reason)
        end

      {:ok, _, state} ->
        stop_selected(state, mode, :selected_listing_fetch_failed)

      {:error, state} ->
        state
    end
  end

  defp collect_links(links, source, metadata, state, http, client, mode) do
    Enum.reduce_while(links, state, fn link, state ->
      link =
        Map.update!(link, :headings, fn headings ->
          Enum.map(headings, fn {level, text} -> %{level: level, text: text} end)
        end)

      metadata = Map.merge(Map.drop(link, [:comparison_url]), metadata)

      case fetch(source, link.url, :pdf, metadata, state, http, client) do
        {:ok, %{outcome: :success}, state} -> {:cont, state}
        {:ok, _, state} -> {:cont, stop_selected(state, mode, :selected_pdf_fetch_failed)}
        {:error, state} -> {:halt, state}
      end
    end)
  end

  defp stop_selected(state, :prefix, _), do: state
  defp stop_selected(state, {:selected, _}, reason), do: %{state | stopped: reason}

  defp discover(_, remaining_operations, _) when remaining_operations <= 0,
    do: {:error, :operation_budget_exhausted}

  defp discover(result, remaining_operations, :prefix),
    do: Discovery.links(result.final_url, result.bytes, max_links: remaining_operations)

  defp discover(result, _, {:selected, pdf_url}) do
    with {:ok, link} <- Discovery.select(result.final_url, result.bytes, pdf_url) do
      {:ok, [link]}
    end
  end

  defp fetch(source, url, kind, metadata, state, http, client) do
    case RunBudget.fetch(state.budget, url, Keyword.put(http, :kind, kind)) do
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
