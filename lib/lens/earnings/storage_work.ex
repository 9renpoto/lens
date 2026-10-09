defmodule Lens.Earnings.StorageWork do
  @moduledoc "Durable, leased RustFS preparation and recovery (ADR 0006)."
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias Lens.Earnings.{Acquisition, Original, Release, RustFS, StorageFence, StorageRetryAudit}
  alias Lens.Repo
  @primary_key {:id, :binary_id, autogenerate: true}
  @provenance [:acquisition_id, :issuer_code, :url, :acquired_at]
  @facts @provenance ++ [:release, :endpoint, :bucket, :key, :sha256, :byte_size]
  @delays %{1 => 60, 2 => 300, 3 => 1800}
  @lease_seconds 120

  schema "earnings_storage_work" do
    field(:acquisition_id, :string)
    field(:issuer_code, :string)
    field(:url, :string)
    field(:acquired_at, :utc_datetime_usec)
    field(:release, :map)
    field(:endpoint, :string)
    field(:bucket, :string)
    field(:key, :string)
    field(:sha256, :string)
    field(:byte_size, :integer)
    field(:bytes, :binary, redact: true)
    field(:status, :string, default: "pending")
    field(:attempts, :integer, default: 0)
    field(:manual_attempts, :integer, default: 0)
    field(:manual_pending, :boolean, default: false)
    field(:last_failure, :string)
    field(:next_attempt_at, :utc_datetime_usec)
    field(:lease_token, :binary_id)
    field(:lease_expires_at, :utc_datetime_usec)
    field(:active_audit_id, :binary_id)
    field(:acquisition_record_id, :binary_id)
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Commit accepted bytes and immutable provenance before any object I/O."
  def prepare(attrs, %RustFS{} = client) do
    if Repo.in_transaction?() do
      {:error, :transaction_open}
    else
      with {:ok, facts} <- validate(attrs, client) do
        Repo.transaction(fn ->
          StorageFence.assert_writable!()
          unless compatible_acquisition?(facts), do: Repo.rollback(:acquisition_conflict)
          changeset = change(%__MODULE__{}, facts) |> unique_constraint(:acquisition_id)
          Repo.insert!(changeset, on_conflict: :nothing, conflict_target: :acquisition_id)
          existing = Repo.get_by!(__MODULE__, acquisition_id: facts.acquisition_id)

          if Map.take(existing, @facts) == Map.take(facts, @facts),
            do: existing,
            else: Repo.rollback(:acquisition_conflict)
        end)
      end
    end
  end

  @doc "Claim one eligible attempt, durably consuming its budget before object I/O."
  def claim(id, now \\ DateTime.utc_now()) do
    transact(fn ->
      work = locked(id)

      cond do
        is_nil(work) ->
          {:error, :not_found}

        work.status == "running" and DateTime.compare(now, work.lease_expires_at) != :lt ->
          fail(work, :lease_expired, work.lease_expires_at)
          {:error, :not_eligible}

        eligible?(work, now) ->
          manual = work.manual_pending

          {:ok,
           Repo.update!(
             change(work, %{
               status: "running",
               attempts: work.attempts + if(manual, do: 0, else: 1),
               manual_attempts: work.manual_attempts + if(manual, do: 1, else: 0),
               manual_pending: false,
               next_attempt_at: nil,
               lease_token: Ecto.UUID.generate(),
               lease_expires_at: DateTime.add(now, @lease_seconds, :second)
             })
           )}

        true ->
          {:error, :not_eligible}
      end
    end)
  end

  @doc "Complete only the current unexpired lease; acquisition and payload cleanup commit together."
  def finish(%__MODULE__{} = claim, result, now \\ DateTime.utc_now()) do
    outcome =
      Repo.transaction(fn ->
        StorageFence.assert_writable!()
        work = locked(claim.id)

        unless work && work.status == "running" && work.lease_token == claim.lease_token &&
                 DateTime.compare(now, work.lease_expires_at) == :lt,
               do: Repo.rollback(:stale_claim)

        case result do
          {:ok, bytes} ->
            if byte_size(bytes) != work.byte_size or hash(bytes) != work.sha256,
              do: fail(work, :integrity_error, now),
              else: complete(work, bytes, nil, now)

          {:ok, bytes, reference} ->
            if byte_size(bytes) != work.byte_size or hash(bytes) != work.sha256 or
                 Map.take(reference, [:key, :sha256, :byte_size]) !=
                   Map.take(work, [:key, :sha256, :byte_size]),
               do: fail(work, :integrity_error, now),
               else: complete(work, bytes, reference, now)

          {:error, reason} ->
            fail(work, reason, now)
        end
      end)

    case outcome do
      {:error, :acquisition_conflict} ->
        case finish(claim, {:error, :acquisition_conflict}, now) do
          {:ok, _} -> outcome
          error -> error
        end

      other ->
        other
    end
  end

  @doc "Check RustFS first, writing only retained bytes when absent; never fetch a publisher."
  def recover(id, %RustFS{} = client, now \\ DateTime.utc_now()) do
    elapsed = System.monotonic_time(:millisecond)

    cond do
      Repo.in_transaction?() ->
        {:error, :transaction_open}

      true ->
        with {:ok, work} <- destination(id, client),
             {:ok, claim} <- claim(work.id, now) do
          reference = Map.take(claim, [:key, :sha256, :byte_size])

          result =
            case RustFS.get(client, reference) do
              {:error, :not_found} ->
                case RustFS.put(client, claim.bytes) do
                  {:ok, saved_reference} -> {:ok, claim.bytes, saved_reference}
                  error -> error
                end

              {:ok, bytes} ->
                {:ok, bytes, reference}

              other ->
                other
            end

          # Preserve elapsed time when a deterministic clock is supplied by a caller.
          finish(
            claim,
            result,
            DateTime.add(now, System.monotonic_time(:millisecond) - elapsed, :millisecond)
          )
        end
    end
  end

  @doc "Schedule exactly one extra attempt and record the operator, without resetting automatic budget."
  def manual_retry(id, operator, now \\ DateTime.utc_now()) do
    if is_binary(operator) and String.trim(operator) != "" and byte_size(operator) <= 200 do
      transact(fn ->
        work = locked(id)

        cond do
          is_nil(work) ->
            {:error, :not_found}

          work.status not in ["attention", "exhausted"] ->
            {:error, :not_eligible}

          true ->
            audit =
              Repo.insert!(%StorageRetryAudit{
                work_id: work.id,
                operator: operator,
                status: "queued",
                requested_at: now
              })

            {:ok,
             Repo.update!(
               change(work, %{
                 status: "pending",
                 manual_pending: true,
                 next_attempt_at: now,
                 active_audit_id: audit.id
               })
             )}
        end
      end)
    else
      {:error, :invalid_operator}
    end
  end

  @doc "List unfinished metadata, excluding retained PDF bytes, in bounded pages."
  def unfinished(limit \\ 100, offset \\ 0)
      when limit in 1..100 and is_integer(offset) and offset >= 0 do
    Repo.all(
      from(w in __MODULE__,
        where: w.status != "completed",
        order_by: [asc: w.inserted_at, asc: w.id],
        limit: ^limit,
        offset: ^offset,
        select:
          map(w, [
            :id,
            :acquisition_id,
            :status,
            :attempts,
            :manual_attempts,
            :last_failure,
            :next_attempt_at,
            :lease_expires_at
          ])
      )
    )
  end

  def audit(id),
    do:
      Repo.all(
        from(a in StorageRetryAudit,
          where: a.work_id == ^id,
          order_by: [asc: a.requested_at, asc: a.id]
        )
      )

  @doc "Run a bounded recovery batch, including expired leases; safe for periodic invocation after restart."
  def recover_due(client, limit \\ 10) when limit in 1..100 do
    now = DateTime.utc_now()

    ids =
      Repo.all(
        from(w in __MODULE__,
          where:
            (w.status == "pending" and (is_nil(w.next_attempt_at) or w.next_attempt_at <= ^now)) or
              (w.status == "running" and w.lease_expires_at <= ^now),
          order_by: [asc: w.inserted_at, asc: w.id],
          limit: ^limit,
          select: w.id
        )
      )

    Enum.map(ids, &{&1, recover_item(&1, client)})
  end

  defp recover_item(id, {:error, reason}) do
    with {:ok, claim} <- claim(id), do: finish(claim, {:error, reason})
  end

  defp recover_item(id, client), do: recover(id, client)

  defp compatible_acquisition?(facts) do
    case Repo.get_by(Acquisition, acquisition_id: facts.acquisition_id) do
      nil ->
        true

      acquisition ->
        acquisition.status == "success" and
          Map.take(acquisition, @provenance) == Map.take(facts, @provenance) and
          Repo.exists?(
            from(o in Original,
              where:
                o.id == ^acquisition.original_id and
                  o.sha256 == ^facts.sha256 and o.byte_size == ^facts.byte_size
            )
          ) and
          compatible_release?(acquisition.release_id, facts.release)
    end
  end

  defp compatible_release?(_, nil), do: true
  defp compatible_release?(nil, _), do: false

  defp compatible_release?(id, expected) do
    actual =
      Repo.get!(Release, id)
      |> Map.take([:issuer_code, :fiscal_year_end, :period, :category])
      |> Jason.encode!()
      |> Jason.decode!()

    actual == expected
  end

  defp validate(%{bytes: bytes} = attrs, client)
       when is_binary(bytes) and byte_size(bytes) in 1..20_971_520 do
    base = Acquisition.provenance_changeset(%Acquisition{}, attrs)

    with {:ok, provenance} <- apply_action(base, :insert),
         {:ok, release} <- identity(Map.get(attrs, :release), provenance.issuer_code) do
      sha256 = hash(bytes)

      {:ok,
       Map.take(provenance, @provenance)
       |> Map.merge(%{
         bytes: bytes,
         release: release,
         endpoint: client.endpoint,
         bucket: client.bucket,
         sha256: sha256,
         byte_size: byte_size(bytes),
         key: "earnings/originals/sha256/" <> sha256 <> ".pdf"
       })}
    end
  end

  defp validate(_, _), do: {:error, :invalid_bytes}

  defp identity(nil, _), do: {:ok, nil}

  defp identity(attrs, issuer) when is_map(attrs) do
    changeset = Release.changeset(%Release{}, Map.put(attrs, :issuer_code, issuer))

    with {:ok, release} <- apply_action(changeset, :insert),
         true <- release.issuer_code == issuer do
      {:ok,
       release
       |> Map.take([:issuer_code, :fiscal_year_end, :period, :category])
       |> Jason.encode!()
       |> Jason.decode!()}
    else
      _ -> {:error, :invalid_identity}
    end
  end

  defp identity(_, _), do: {:error, :invalid_identity}

  defp destination(id, client) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %__MODULE__{} = work <- Repo.get(__MODULE__, uuid) do
      if work.endpoint == client.endpoint and work.bucket == client.bucket do
        {:ok, work}
      else
        transact(fn ->
          current = locked(work.id)

          if current.status == "pending" do
            audit_finish(current, "failed", "destination_mismatch", DateTime.utc_now())

            Repo.update!(
              change(current, %{
                status: "attention",
                last_failure: "destination_mismatch",
                next_attempt_at: nil,
                manual_pending: false,
                active_audit_id: nil
              })
            )
          end

          {:error, :destination_mismatch}
        end)
      end
    else
      _ -> {:error, :not_found}
    end
  end

  defp locked(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.one(from(w in __MODULE__, where: w.id == ^uuid, lock: "FOR UPDATE"))
      :error -> nil
    end
  end

  defp eligible?(work, now),
    do:
      work.status == "pending" and
        (work.manual_pending or work.attempts < 4) and
        (is_nil(work.next_attempt_at) or DateTime.compare(now, work.next_attempt_at) != :lt)

  defp complete(work, bytes, reference, now) do
    attrs =
      Map.take(work, @provenance)
      |> Map.put(:bytes, bytes)
      |> Map.put(:release, release_attrs(work.release))

    attrs = if reference, do: Map.put(attrs, :storage_reference, reference), else: attrs

    case Lens.Earnings.record_success(attrs) do
      {:ok, result} ->
        audit_finish(work, "completed", nil, now)

        Repo.update!(
          change(work, %{
            status: "completed",
            bytes: nil,
            acquisition_record_id: result.acquisition.id,
            lease_token: nil,
            lease_expires_at: nil,
            active_audit_id: nil,
            last_failure: nil
          })
        )

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp release_attrs(nil), do: nil

  defp release_attrs(attrs) do
    %{
      issuer_code: attrs["issuer_code"],
      fiscal_year_end: attrs["fiscal_year_end"],
      period: attrs["period"],
      category: attrs["category"]
    }
  end

  defp fail(work, reason, now) do
    reason = failure_name(reason)
    manual = not is_nil(work.active_audit_id)

    attention =
      reason in ~w(unauthorized integrity_error invalid_configuration not_configured invalid_reference not_found acquisition_conflict) or
        String.starts_with?(reason, "http_") or manual

    status =
      cond do
        attention -> "attention"
        work.attempts >= 4 -> "exhausted"
        true -> "pending"
      end

    audit_finish(work, "failed", reason, now)

    Repo.update!(
      change(work, %{
        status: status,
        last_failure: reason,
        lease_token: nil,
        lease_expires_at: nil,
        active_audit_id: nil,
        next_attempt_at:
          if(status == "pending",
            do: DateTime.add(now, Map.fetch!(@delays, work.attempts), :second),
            else: nil
          )
      })
    )
  end

  defp audit_finish(%{active_audit_id: nil}, _, _, _), do: :ok

  defp audit_finish(work, status, failure, now) do
    Repo.update_all(from(a in StorageRetryAudit, where: a.id == ^work.active_audit_id),
      set: [status: status, failure: failure, finished_at: now]
    )
  end

  defp failure_name(reason)
       when reason in [
              :acquisition_conflict,
              :not_found,
              :unauthorized,
              :integrity_error,
              :invalid_configuration,
              :not_configured,
              :invalid_reference,
              :timeout,
              :transport_error,
              :unavailable,
              :conflict,
              :lease_expired
            ],
       do: Atom.to_string(reason)

  defp failure_name({:http_error, status}) when is_integer(status),
    do: "http_" <> Integer.to_string(status)

  defp failure_name(_), do: "storage_error"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp transact(fun) do
    if Repo.in_transaction?() do
      {:error, :transaction_open}
    else
      case Repo.transaction(fn ->
             StorageFence.assert_writable!()
             fun.()
           end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
