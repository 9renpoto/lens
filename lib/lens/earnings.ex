defmodule Lens.Earnings do
  @moduledoc "Persistence for earnings PDF originals and their acquisition attempts."

  import Ecto.Query

  alias Lens.Earnings.{Acquisition, Original, Release, RustFS}
  alias Lens.Repo

  @max_original_bytes 20_971_520

  @doc "Record one successful download. `acquisition_id` identifies the actual attempt across persistence retries."
  def record_success(%{bytes: bytes} = attrs) when is_binary(bytes) do
    if byte_size(bytes) > @max_original_bytes do
      case record_failure(Map.put(attrs, :reason, "too_large")) do
        {:ok, failure} -> {:error, :too_large, failure}
        other -> other
      end
    else
      Repo.transaction(fn ->
        with {:ok, base, identity} <- validate_success(attrs),
             :ok <- validate_storage_reference(Map.get(attrs, :storage_reference), bytes),
             {:ok, result} <-
               do_record_success(base, bytes, identity, Map.get(attrs, :storage_reference)) do
          result
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def record_success(_), do: {:error, :invalid_bytes}

  @doc "Validate acquisition provenance and optional release identity without persistence."
  def validate_success(attrs) do
    with {:ok, base} <- validated_common(attrs),
         {:ok, identity} <-
           release_identity(Map.get(attrs, :release), Map.get(attrs, :issuer_code)) do
      {:ok, base, identity}
    end
  end

  @doc "Record a failed download or rejected original without creating a successful observation."
  def record_failure(attrs) when is_map(attrs) do
    reason = Map.get(attrs, :reason)

    Repo.transaction(fn ->
      acquisition_attrs =
        common_attrs(attrs) |> Map.merge(%{status: "failed", failure_reason: reason})

      changeset = Acquisition.changeset(%Acquisition{}, acquisition_attrs)

      if changeset.valid? do
        acquisition_attrs = normalized_attempt(changeset)
        existing = Repo.get_by(Acquisition, acquisition_id: acquisition_attrs.acquisition_id)

        if existing do
          if same_attempt?(existing, acquisition_attrs),
            do: existing,
            else: Repo.rollback(:acquisition_conflict)
        else
          insert_acquisition(changeset, acquisition_attrs)
        end
      else
        Repo.rollback(changeset)
      end
    end)
  end

  @doc "Explicitly attach a pending successful acquisition to a release identity using its stable acquisition_id."
  def confirm_identity(acquisition_id, identity) do
    Repo.transaction(fn ->
      acquisition = Repo.get_by(Acquisition, acquisition_id: acquisition_id)

      cond do
        is_nil(acquisition) -> Repo.rollback(:not_found)
        acquisition.status != "success" -> Repo.rollback(:not_successful)
        true -> confirm_success_identity(acquisition, identity)
      end
    end)
  end

  @doc "Fetch and verify the exact retained RustFS bytes by original ID."
  def original_bytes(id, options \\ []) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Original{} = original <- Repo.get(Original, id) do
      read_rustfs(original, options)
    else
      _ -> :error
    end
  end

  defp do_record_success(base, bytes, identity, storage_reference) do
    sha256 = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    existing = Repo.get_by(Acquisition, acquisition_id: base.acquisition_id)

    if existing do
      existing_success(existing, base, sha256, identity, storage_reference)
    else
      with {:ok, original} <- upsert_original(bytes, sha256, storage_reference),
           {:ok, release} <- upsert_release(identity),
           acquisition_attrs <-
             Map.merge(base, %{
               status: "success",
               original_id: original.id,
               release_id: release && release.id
             }),
           changeset <- Acquisition.changeset(%Acquisition{}, acquisition_attrs),
           {:ok, acquisition} <- insert_acquisition_result(changeset, acquisition_attrs) do
        {:ok, %{acquisition: acquisition, original: original, release: release}}
      end
    end
  end

  defp existing_success(existing, base, sha256, identity, storage_reference) do
    original =
      if existing.original_id do
        Repo.one!(
          from(o in Original,
            where: o.id == ^existing.original_id,
            select: o
          )
        )
      end

    release = if existing.release_id, do: Repo.get(Release, existing.release_id)

    if existing.status == "success" and same_common?(existing, base) and
         original.sha256 == sha256 and identity_matches?(release, identity) do
      case matching_reference(original, storage_reference) do
        :ok -> {:ok, %{acquisition: existing, original: original, release: release}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :acquisition_conflict}
    end
  end

  defp confirm_success_identity(acquisition, identity) do
    with {:ok, identity} <- release_identity(identity, acquisition.issuer_code),
         false <- is_nil(identity),
         {:ok, release} <- upsert_release(identity) do
      cond do
        acquisition.release_id == release.id ->
          acquisition

        not is_nil(acquisition.release_id) ->
          Repo.rollback(:identity_conflict)

        true ->
          Repo.update_all(
            from(a in Acquisition, where: a.id == ^acquisition.id and is_nil(a.release_id)),
            set: [release_id: release.id]
          )

          confirmed = Repo.get!(Acquisition, acquisition.id)

          if confirmed.release_id == release.id,
            do: confirmed,
            else: Repo.rollback(:identity_conflict)
      end
    else
      true -> Repo.rollback(:invalid_identity)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp upsert_original(_bytes, sha256, reference) do
    changeset =
      Original.changeset(%Original{}, Map.put(reference, :verified_at, DateTime.utc_now()))

    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :sha256) do
      {:ok, _} ->
        original = Repo.get_by!(Original, sha256: sha256)
        with :ok <- matching_reference(original, reference), do: {:ok, original}

      error ->
        error
    end
  end

  defp matching_reference(original, reference) do
    if Map.take(original, [:key, :endpoint, :bucket, :sha256, :byte_size]) == reference,
      do: :ok,
      else: {:error, :reference_conflict}
  end

  defp validate_storage_reference(
         %{key: key, endpoint: endpoint, bucket: bucket, sha256: sha256, byte_size: size},
         bytes
       )
       when is_binary(endpoint) and endpoint != "" and is_binary(bucket) and bucket != "" do
    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    if key == "earnings/originals/sha256/#{digest}.pdf" and sha256 == digest and
         size == byte_size(bytes),
       do: :ok,
       else: {:error, :integrity_error}
  end

  defp validate_storage_reference(_, _), do: {:error, :invalid_reference}

  defp upsert_release(nil), do: {:ok, nil}

  defp upsert_release(identity) do
    changeset = Release.changeset(%Release{}, identity)

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:issuer_code, :fiscal_year_end, :period, :category]
         ) do
      {:ok, _} -> {:ok, Repo.get_by!(Release, identity)}
      error -> error
    end
  end

  defp insert_acquisition(changeset, attrs) do
    case insert_acquisition_result(changeset, attrs) do
      {:ok, acquisition} -> acquisition
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp insert_acquisition_result(changeset, _attrs) do
    attrs = normalized_attempt(changeset)

    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :acquisition_id) do
      {:ok, _} ->
        acquisition = Repo.get_by!(Acquisition, acquisition_id: attrs.acquisition_id)

        if same_attempt?(acquisition, attrs),
          do: {:ok, acquisition},
          else: {:error, :acquisition_conflict}

      error ->
        error
    end
  end

  defp release_identity(nil, _issuer), do: {:ok, nil}

  defp release_identity(identity, issuer) when is_map(identity) do
    attrs = Map.put(identity, :issuer_code, issuer)
    changeset = Release.changeset(%Release{}, attrs)

    if changeset.valid?,
      do:
        {:ok,
         Ecto.Changeset.apply_changes(changeset)
         |> Map.take([:issuer_code, :fiscal_year_end, :period, :category])},
      else: {:error, changeset}
  end

  defp release_identity(_, _), do: {:error, :invalid_identity}

  defp identity_matches?(_release, nil), do: true
  defp identity_matches?(nil, _identity), do: false
  defp identity_matches?(release, identity), do: Map.take(release, Map.keys(identity)) == identity

  defp read_rustfs(original, options) do
    with {:ok, client} <- rustfs_client(options),
         :ok <- validate_destination(client, original),
         {:ok, bytes} <- RustFS.get(client, Map.take(original, [:key, :sha256, :byte_size])) do
      {:ok, bytes}
    end
  end

  defp rustfs_client(options) do
    case Keyword.get(options, :rustfs) do
      %RustFS{} = client -> {:ok, client}
      nil -> RustFS.new()
      _ -> {:error, :invalid_configuration}
    end
  end

  defp validate_destination(client, location) do
    if client.endpoint == location.endpoint and client.bucket == location.bucket,
      do: :ok,
      else: {:error, :destination_mismatch}
  end

  defp common_attrs(attrs) do
    Map.take(attrs, [:acquisition_id, :issuer_code, :url, :acquired_at])
  end

  defp validated_common(attrs) do
    changeset = Acquisition.provenance_changeset(%Acquisition{}, common_attrs(attrs))

    if changeset.valid?,
      do: {:ok, changeset |> Ecto.Changeset.apply_changes() |> common_attrs()},
      else: {:error, changeset}
  end

  defp normalized_attempt(changeset) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.take([
      :acquisition_id,
      :issuer_code,
      :url,
      :acquired_at,
      :status,
      :failure_reason,
      :original_id,
      :release_id
    ])
  end

  defp same_common?(acquisition, attrs) do
    Enum.all?(attrs, fn {key, value} -> Map.get(acquisition, key) == value end)
  end

  defp same_attempt?(acquisition, attrs) do
    same_common?(acquisition, common_attrs(attrs)) and
      acquisition.status == attrs.status and
      acquisition.failure_reason == Map.get(attrs, :failure_reason) and
      acquisition.original_id == Map.get(attrs, :original_id) and
      acquisition.release_id == Map.get(attrs, :release_id)
  end
end
