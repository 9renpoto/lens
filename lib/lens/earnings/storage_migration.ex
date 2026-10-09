defmodule Lens.Earnings.StorageMigration do
  @moduledoc "Bounded, resumable migration and rollback of retained original PDFs."
  import Ecto.Query
  alias Lens.Earnings.{Original, OriginalStorage, RustFS, StorageFence}
  alias Lens.Repo

  def migrate_batch(%RustFS{} = client, options \\ []) do
    with {:ok, limit, cursor} <- validate_options(options) do
      StorageFence.with_migration(fn ->
        ids = original_ids(limit, cursor)

        {migrated, skipped, failures} =
          Enum.reduce(ids, {0, 0, []}, fn id, counts ->
            case migrate_one(id, client) do
              :migrated -> increment(counts, :migrated)
              :skipped -> increment(counts, :skipped)
              {:error, reason} -> add_failure(counts, id, reason)
            end
          end)

        {:ok,
         %{
           migrated: migrated,
           skipped: skipped,
           failures: Enum.reverse(failures),
           next_after: resumable_cursor(ids, failures)
         }}
      end)
    end
  end

  def rollback_batch(%RustFS{} = client, options \\ []) do
    with {:ok, limit, cursor} <- validate_options(options) do
      StorageFence.with_rollback_batch(fn ->
        ids = rustfs_ids(limit, cursor)

        {restored, skipped, failures} =
          Enum.reduce(ids, {0, 0, []}, fn id, counts ->
            case rollback_one(id, client) do
              :restored -> increment(counts, :restored)
              :skipped -> increment(counts, :skipped)
              {:error, reason} -> add_failure(counts, id, reason)
            end
          end)

        remaining = OriginalStorage.count_active("rustfs")

        {:ok,
         %{
           restored: restored,
           skipped: skipped,
           failures: Enum.reverse(failures),
           remaining: remaining,
           complete?: remaining == 0,
           next_after: resumable_cursor(ids, failures)
         }}
      end)
    end
  end

  defp original_ids(limit, cursor) do
    query =
      from(o in Original,
        order_by: [asc: o.id],
        limit: ^limit,
        select: o.id
      )

    query = if cursor, do: where(query, [o], o.id > ^cursor), else: query
    Repo.all(query)
  end

  defp rustfs_ids(limit, cursor) do
    query =
      from(s in Lens.Earnings.OriginalReadLocation,
        join: l in Lens.Earnings.OriginalStorageLocation,
        on: l.id == s.location_id,
        where: l.backend == "rustfs",
        order_by: [asc: s.original_id],
        limit: ^limit,
        select: s.original_id
      )

    query = if cursor, do: where(query, [s, _l], s.original_id > ^cursor), else: query
    Repo.all(query)
  end

  defp migrate_one(id, client) do
    original = Repo.get(Original, id)

    cond do
      is_nil(original) ->
        {:error, :not_found}

      OriginalStorage.active_backend(id) == "rustfs" ->
        :skipped

      not is_binary(original.bytes) ->
        {:error, :original_unavailable}

      true ->
        with :ok <- validate_bytes(original, original.bytes),
             {:ok, reference} <- RustFS.put(client, original.bytes),
             {:ok, copied_bytes} <- RustFS.get(client, reference),
             true <- copied_bytes == original.bytes,
             {:ok, _location} <- OriginalStorage.switch_to_rustfs(original, reference) do
          :migrated
        else
          false -> {:error, :integrity_error}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp rollback_one(id, client) do
    case OriginalStorage.read_location(id) do
      {:ok, nil} ->
        :skipped

      {:ok, %{backend: "postgresql"}} ->
        :skipped

      {:ok, %{backend: "rustfs"} = location} ->
        original = Repo.get(Original, id)

        cond do
          is_nil(original) ->
            {:error, :not_found}

          is_binary(original.bytes) ->
            with :ok <- validate_bytes(original, original.bytes),
                 {:ok, _} <- OriginalStorage.switch_to_postgresql(id, original.bytes) do
              :restored
            end

          true ->
            reference = %{
              key: location.key,
              sha256: location.sha256,
              byte_size: location.byte_size
            }

            with {:ok, bytes} <- RustFS.get(client, reference),
                 :ok <- validate_bytes(original, bytes),
                 {:ok, _} <- OriginalStorage.switch_to_postgresql(id, bytes) do
              :restored
            end
        end
    end
  end

  defp validate_bytes(original, bytes) do
    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    if byte_size(bytes) == original.byte_size and digest == original.sha256,
      do: :ok,
      else: {:error, :integrity_error}
  end

  defp validate_options(options) do
    limit = Keyword.get(options, :limit, 10)
    cursor = Keyword.get(options, :after)

    if is_integer(limit) and limit in 1..100 and
         (is_nil(cursor) or match?({:ok, _}, Ecto.UUID.cast(cursor))) do
      {:ok, limit, cursor}
    else
      {:error, :invalid_options}
    end
  end

  defp increment({migrated, skipped, failures}, :migrated),
    do: {migrated + 1, skipped, failures}

  defp increment({count, skipped, failures}, :restored),
    do: {count + 1, skipped, failures}

  defp increment({migrated, skipped, failures}, :skipped),
    do: {migrated, skipped + 1, failures}

  defp add_failure({migrated, skipped, failures}, id, reason),
    do: {migrated, skipped, [%{original_id: id, reason: failure_name(reason)} | failures]}

  defp resumable_cursor(ids, []), do: List.last(ids)

  defp resumable_cursor(ids, failures) do
    failed_ids = MapSet.new(failures, &Map.fetch!(&1, :original_id))
    first_failed_id = Enum.find(ids, &MapSet.member?(failed_ids, &1))

    case Enum.find_index(ids, &(&1 == first_failed_id)) do
      index when is_integer(index) and index > 0 -> Enum.at(ids, index - 1)
      _ -> nil
    end
  end

  defp failure_name(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_name({:http_error, status}), do: "http_#{status}"
  defp failure_name(_), do: "storage_error"
end
