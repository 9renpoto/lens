defmodule Lens.Earnings.OriginalStorage do
  @moduledoc "Tracks verified physical locations and the active read location for original PDFs."
  import Ecto.Query
  alias Lens.Earnings.{Original, OriginalReadLocation, OriginalStorageLocation}
  alias Lens.Repo

  def read_location(original_id) do
    selection =
      Repo.one(
        from(s in OriginalReadLocation,
          join: l in OriginalStorageLocation,
          on: l.id == s.location_id,
          where: s.original_id == ^original_id,
          select: l
        )
      )

    {:ok, selection}
  end

  def active_backend(original_id) do
    case read_location(original_id) do
      {:ok, nil} -> "postgresql"
      {:ok, location} -> location.backend
    end
  end

  def switch_to_rustfs(%Original{} = original, reference) do
    with :ok <- validate_bytes(original, original.bytes),
         true <- reference.sha256 == original.sha256,
         true <- reference.byte_size == original.byte_size do
      select_rustfs(original, reference)
    else
      false -> {:error, :integrity_error}
      {:error, _} = error -> error
    end
  end

  def switch_to_postgresql(original_id, bytes) when is_binary(bytes) do
    transact(fn ->
      original =
        Repo.one(from(o in Original, where: o.id == ^original_id, lock: "FOR UPDATE"))

      with %Original{} <- original,
           :ok <- validate_bytes(original, bytes),
           :ok <- hydrate(original, bytes),
           {:ok, postgresql} <- ensure_location(postgresql_attrs(%{original | bytes: bytes})),
           :ok <- select_location(original.id, postgresql.id) do
        {:ok, postgresql}
      else
        nil -> {:error, :not_found}
        false -> {:error, :integrity_error}
        {:error, _} = error -> error
      end
    end)
  end

  def switch_to_postgresql(_, _), do: {:error, :invalid_bytes}

  def count_active(backend) do
    Repo.aggregate(
      from(s in OriginalReadLocation,
        join: l in OriginalStorageLocation,
        on: l.id == s.location_id,
        where: l.backend == ^backend
      ),
      :count
    )
  end

  def select_rustfs(%Original{} = original, reference) do
    transact(fn ->
      with :ok <- validate_reference(original, reference),
           {:ok, _postgresql} <- maybe_ensure_postgresql_location(original),
           {:ok, rustfs} <- ensure_location(rustfs_attrs(original, reference)),
           :ok <- select_location(original.id, rustfs.id) do
        {:ok, rustfs}
      end
    end)
  end

  defp hydrate(%Original{bytes: bytes}, bytes) when is_binary(bytes), do: :ok

  defp hydrate(%Original{bytes: nil} = original, bytes) do
    query =
      from(o in Original,
        where:
          o.id == ^original.id and is_nil(o.bytes) and o.sha256 == ^original.sha256 and
            o.byte_size == ^original.byte_size
      )

    case Repo.update_all(query, set: [bytes: bytes]) do
      {1, _} -> :ok
      {0, _} -> {:error, :original_conflict}
    end
  end

  defp hydrate(_, _), do: {:error, :original_conflict}

  defp postgresql_attrs(original) do
    %{
      original_id: original.id,
      backend: "postgresql",
      key: nil,
      endpoint: nil,
      bucket: nil,
      sha256: original.sha256,
      byte_size: original.byte_size,
      verified_at: DateTime.utc_now()
    }
  end

  defp maybe_ensure_postgresql_location(%Original{bytes: bytes} = original)
       when is_binary(bytes) do
    with :ok <- validate_bytes(original, bytes),
         {:ok, location} <- ensure_location(postgresql_attrs(original)) do
      {:ok, location}
    end
  end

  defp maybe_ensure_postgresql_location(%Original{bytes: nil}), do: {:ok, nil}

  defp rustfs_attrs(original, reference) do
    %{
      original_id: original.id,
      backend: "rustfs",
      key: reference.key,
      endpoint: Map.get(reference, :endpoint),
      bucket: Map.get(reference, :bucket),
      sha256: reference.sha256,
      byte_size: reference.byte_size,
      verified_at: DateTime.utc_now()
    }
  end

  defp ensure_location(attrs) do
    changeset = OriginalStorageLocation.changeset(%OriginalStorageLocation{}, attrs)

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:original_id, :backend]
         ) do
      {:ok, _} ->
        location =
          Repo.get_by!(OriginalStorageLocation,
            original_id: attrs.original_id,
            backend: attrs.backend
          )

        if Map.take(location, [:key, :endpoint, :bucket, :sha256, :byte_size]) ==
             Map.take(attrs, [:key, :endpoint, :bucket, :sha256, :byte_size]),
           do: {:ok, location},
           else: {:error, :location_conflict}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp select_location(original_id, location_id) do
    case Repo.get(OriginalReadLocation, original_id) do
      nil ->
        %OriginalReadLocation{}
        |> OriginalReadLocation.changeset(%{original_id: original_id, location_id: location_id})
        |> Repo.insert(on_conflict: :nothing, conflict_target: :original_id)
        |> case do
          {:ok, _} ->
            if Repo.get!(OriginalReadLocation, original_id).location_id == location_id,
              do: :ok,
              else: {:error, :location_conflict}

          {:error, reason} ->
            {:error, reason}
        end

      %{location_id: ^location_id} ->
        :ok

      selection ->
        selection
        |> OriginalReadLocation.changeset(%{location_id: location_id})
        |> Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_bytes(%Original{} = original, bytes) when is_binary(bytes) do
    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    if byte_size(bytes) == original.byte_size and digest == original.sha256,
      do: :ok,
      else: {:error, :integrity_error}
  end

  defp validate_reference(original, %{key: key, sha256: sha256, byte_size: byte_size})
       when is_binary(key) and is_binary(sha256) and is_integer(byte_size) and byte_size > 0 do
    expected_key = "earnings/originals/sha256/#{sha256}.pdf"

    if sha256 == original.sha256 and byte_size == original.byte_size and key == expected_key,
      do: :ok,
      else: {:error, :integrity_error}
  end

  defp validate_reference(_, _), do: {:error, :invalid_reference}

  defp transact(fun) do
    case Repo.transaction(fn ->
           case fun.() do
             {:error, reason} -> Repo.rollback(reason)
             result -> result
           end
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
