defmodule Lens.Ingestion.EarningsUpdates do
  @moduledoc "Persists a subscription baseline and emits only feed-visible updates."

  import Ecto.Query
  alias Lens.Content.Source
  alias Lens.{ErrorReporter, Repo}

  @spec observe(Source.t(), [map()], map(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  def observe(source, entries, headers, observed_at) do
    Repo.transaction(fn ->
      current = Repo.one!(from(s in Source, where: s.id == ^source.id, lock: "FOR UPDATE"))

      if current.endpoint_url != source.endpoint_url or
           current.ingestion_mode != "earnings_updates" do
        Repo.rollback(:source_changed)
      end

      baseline? = is_nil(current.feed_baselined_at)
      {signals, invalid} = observe_entries(current, entries, baseline?)

      current
      |> Ecto.Changeset.change(
        feed_baselined_at: current.feed_baselined_at || observed_at,
        etag: Map.get(headers, "etag"),
        last_modified: Map.get(headers, "last-modified"),
        last_attempt_at: observed_at,
        last_success_at: observed_at,
        last_error: nil,
        failure_count: 0
      )
      |> Repo.update!()

      %{signals: signals, invalid_entries: invalid}
    end)
  end

  defp observe_entries(source, entries, baseline?) do
    indexed = Enum.with_index(entries)

    conflicting =
      indexed
      |> Enum.group_by(fn {entry, _} -> item_key(entry) end)
      |> Enum.filter(fn {key, group} ->
        not is_nil(key) and length(Enum.uniq_by(group, fn {entry, _} -> hash(entry) end)) > 1
      end)

    rejected = MapSet.new(Enum.map(conflicting, &elem(&1, 0)))

    errors =
      Enum.map(conflicting, fn {_key, [{_, index} | _]} ->
        ErrorReporter.report(:discovery, :conflicting_item_identity)
        %{index: index, error: "conflicting duplicate item identity"}
      end)

    indexed
    |> Enum.reject(fn {entry, _} -> MapSet.member?(rejected, item_key(entry)) end)
    |> Enum.reduce({[], errors}, fn {entry, index}, {signals, invalid} ->
      case item_key(entry) do
        nil ->
          ErrorReporter.report(:discovery, :missing_item_identity)
          {signals, [%{index: index, error: "missing stable item identity"} | invalid]}

        key ->
          fingerprint = hash(entry)
          source_id = Ecto.UUID.dump!(source.id)

          previous =
            Repo.one(
              from(i in "earnings_feed_items",
                where: i.source_id == ^source_id and i.item_key == ^key,
                select: i.fingerprint
              )
            )

          Repo.insert_all(
            "earnings_feed_items",
            [%{source_id: source_id, item_key: key, fingerprint: fingerprint}],
            on_conflict: {:replace, [:fingerprint]},
            conflict_target: [:source_id, :item_key]
          )

          if not baseline? and previous != fingerprint do
            signal = %{
              source_id: source.id,
              item_key: key,
              change: if(is_nil(previous), do: :new, else: :changed),
              entry: entry
            }

            {[signal | signals], invalid}
          else
            {signals, invalid}
          end
      end
    end)
    |> then(fn {signals, invalid} -> {Enum.reverse(signals), Enum.reverse(invalid)} end)
  end

  defp item_key(entry) do
    cond do
      is_binary(entry.source_entry_id) and String.trim(entry.source_entry_id) != "" ->
        hash({:id, entry.source_entry_id})

      is_binary(entry.canonical_url) ->
        hash({:url, entry.canonical_url})

      true ->
        nil
    end
  end

  defp hash(value),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
end
