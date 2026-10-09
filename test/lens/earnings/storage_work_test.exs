defmodule Lens.Earnings.StorageWorkTest do
  use Lens.DataCase, async: false
  alias Lens.Earnings.{Acquisition, Original, RustFS, StorageWork}
  alias Lens.Earnings

  setup do
    {:ok, client} =
      RustFS.new(
        endpoint: "http://storage.test",
        bucket: "lens-test",
        access_key_id: "test",
        secret_access_key: "secret"
      )

    now = ~U[2026-10-09 05:00:00.000000Z]

    attrs = %{
      acquisition_id: "work-1",
      issuer_code: "1234",
      url: "https://publisher.test/a.pdf",
      acquired_at: now,
      bytes: "%PDF-original"
    }

    %{client: client, now: now, attrs: attrs}
  end

  test "preparation persists payload and provenance without object I/O and rejects conflicts",
       c do
    assert {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    assert work.bytes == c.attrs.bytes
    assert work.status == "pending"
    assert work.attempts == 0
    assert {:ok, same} = StorageWork.prepare(c.attrs, c.client)
    assert same.id == work.id

    assert {:error, :acquisition_conflict} =
             StorageWork.prepare(%{c.attrs | url: "https://other.test/a"}, c.client)

    assert {:error, :acquisition_conflict} =
             StorageWork.prepare(%{c.attrs | bytes: "different"}, c.client)

    assert Repo.aggregate(StorageWork, :count) == 1
    refute Repo.get_by(Acquisition, acquisition_id: c.attrs.acquisition_id)
  end

  test "claim consumes budget before I/O and competing or stale workers cannot complete", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    assert {:ok, first} = StorageWork.claim(work.id, c.now)
    assert first.attempts == 1
    assert {:error, :not_eligible} = StorageWork.claim(work.id, c.now)
    later = DateTime.add(c.now, 120, :second)
    assert {:error, :not_eligible} = StorageWork.claim(work.id, later)
    assert Repo.get!(StorageWork, work.id).next_attempt_at == DateTime.add(later, 60, :second)
    assert {:ok, second} = StorageWork.claim(work.id, DateTime.add(later, 60, :second))
    assert second.attempts == 2
    assert {:error, :stale_claim} = StorageWork.finish(first, {:ok, c.attrs.bytes}, later)

    assert {:ok, completed} =
             StorageWork.finish(second, {:ok, c.attrs.bytes}, DateTime.add(later, 61, :second))

    assert completed.status == "completed"
    assert completed.bytes == nil
    assert Repo.get_by!(Acquisition, acquisition_id: c.attrs.acquisition_id).status == "success"
  end

  test "automatic retries persist one minute, five minute and thirty minute delays then exhaust",
       c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)

    Enum.reduce([60, 300, 1800, nil], c.now, fn delay, now ->
      assert {:ok, claim} = StorageWork.claim(work.id, now)
      assert {:ok, failed} = StorageWork.finish(claim, {:error, :unavailable}, now)
      assert failed.bytes == c.attrs.bytes

      if delay do
        assert failed.status == "pending"
        assert failed.next_attempt_at == DateTime.add(now, delay, :second)
        assert {:error, :not_eligible} = StorageWork.claim(work.id, now)
        failed.next_attempt_at
      else
        assert failed.status == "exhausted"
        assert failed.attempts == 4

        assert {:error, :not_eligible} =
                 StorageWork.claim(work.id, DateTime.add(now, 9999, :second))

        now
      end
    end)

    assert [%{status: "exhausted"}] = StorageWork.unfinished()
  end

  test "attention failures stop automatic retries and manual retry adds audited attempt", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    {:ok, claim} = StorageWork.claim(work.id, c.now)
    assert {:ok, failed} = StorageWork.finish(claim, {:error, :integrity_error}, c.now)
    assert failed.status == "attention"

    assert {:error, :not_eligible} =
             StorageWork.claim(work.id, DateTime.add(c.now, 9999, :second))

    assert {:error, :invalid_operator} = StorageWork.manual_retry(work.id, "", c.now)
    assert {:ok, _} = StorageWork.manual_retry(work.id, "operator-1", c.now)
    assert {:error, :not_eligible} = StorageWork.manual_retry(work.id, "operator-2", c.now)
    {:ok, manual} = StorageWork.claim(work.id, c.now)
    assert manual.attempts == 1
    assert manual.manual_attempts == 1
    assert {:ok, failed} = StorageWork.finish(manual, {:error, :unavailable}, c.now)
    assert failed.status == "attention"
    assert [%{operator: "operator-1", status: "failed"}] = StorageWork.audit(work.id)
  end

  test "recovery checks saved object before writing and completes exactly once", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)

    client = %{
      c.client
      | request:
          Req.new(
            plug: fn conn ->
              assert conn.method == "GET"
              Plug.Conn.send_resp(conn, 200, c.attrs.bytes)
            end
          )
    }

    assert {:ok, completed} = StorageWork.recover(work.id, client, c.now)
    assert completed.status == "completed"
    assert {:error, :not_eligible} = StorageWork.recover(work.id, client, c.now)
    assert Repo.aggregate(Acquisition, :count) == 1

    acquisition = Repo.get_by!(Acquisition, acquisition_id: c.attrs.acquisition_id)
    original = Repo.get!(Original, acquisition.original_id)
    assert original.bytes == nil
    assert Earnings.original_bytes(original.id, rustfs: client) == {:ok, c.attrs.bytes}
  end

  test "missing object writes retained bytes; changed destination never receives I/O", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    wrong = %{c.client | bucket: "other-bucket"}
    assert {:error, :destination_mismatch} = StorageWork.recover(work.id, wrong, c.now)
    assert Repo.get!(StorageWork, work.id).attempts == 0
    assert Repo.get!(StorageWork, work.id).status == "attention"
    assert {:ok, _} = StorageWork.manual_retry(work.id, "operator", c.now)
    {:ok, agent} = Agent.start_link(fn -> false end)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

    client = %{
      c.client
      | request:
          Req.new(
            plug: fn conn ->
              case conn.method do
                "GET" ->
                  Plug.Conn.send_resp(
                    conn,
                    if(Agent.get(agent, & &1), do: 200, else: 404),
                    c.attrs.bytes
                  )

                "PUT" ->
                  {:ok, bytes, conn} = Plug.Conn.read_body(conn)
                  assert bytes == c.attrs.bytes
                  Agent.update(agent, fn _ -> true end)
                  Plug.Conn.send_resp(conn, 200, "")
              end
            end
          )
    }

    assert {:ok, completed} = StorageWork.recover(work.id, client, c.now)
    assert completed.status == "completed"
  end

  test "completion conflict rolls back acquisition and retains prepared bytes", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    {:ok, _} = Lens.Earnings.record_failure(Map.put(c.attrs, :reason, "failed"))
    {:ok, claim} = StorageWork.claim(work.id, c.now)

    assert {:error, :acquisition_conflict} =
             StorageWork.finish(claim, {:ok, c.attrs.bytes}, c.now)

    assert Repo.get!(StorageWork, work.id).bytes == c.attrs.bytes
    assert Repo.get!(StorageWork, work.id).status == "attention"
  end

  test "uncommitted preparation and recovery are rejected", c do
    assert {:ok, {:error, :transaction_open}} =
             Repo.transaction(fn -> StorageWork.prepare(c.attrs, c.client) end)

    {:ok, work} = StorageWork.prepare(c.attrs, c.client)

    assert {:ok, {:error, :transaction_open}} =
             Repo.transaction(fn -> StorageWork.recover(work.id, c.client, c.now) end)

    assert Repo.get!(StorageWork, work.id).attempts == 0
  end

  test "expired final attempt remains exhausted after restart and manual success preserves budget",
       c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)

    last =
      Enum.reduce([60, 300, 1800], c.now, fn delay, now ->
        {:ok, claim} = StorageWork.claim(work.id, now)
        {:ok, _} = StorageWork.finish(claim, {:error, :timeout}, now)
        DateTime.add(now, delay, :second)
      end)

    {:ok, claim} = StorageWork.claim(work.id, last)
    expired = DateTime.add(last, 120, :second)
    assert {:error, :not_eligible} = StorageWork.claim(work.id, expired)
    assert Repo.get!(StorageWork, work.id).status == "exhausted"
    {:ok, _} = StorageWork.manual_retry(work.id, "operator", expired)
    {:ok, manual} = StorageWork.claim(work.id, expired)
    assert manual.attempts == 4
    assert {:error, :stale_claim} = StorageWork.finish(claim, {:ok, c.attrs.bytes}, expired)

    assert {:ok, %{status: "completed"}} =
             StorageWork.finish(manual, {:ok, c.attrs.bytes}, expired)

    assert [%{status: "completed", operator: "operator"}] = StorageWork.audit(work.id)
  end

  test "accepted release identity is retained and completed atomically", c do
    attrs =
      Map.put(c.attrs, :release, %{
        fiscal_year_end: ~D[2026-03-31],
        period: "q1",
        category: "report"
      })

    {:ok, work} = StorageWork.prepare(attrs, c.client)
    {:ok, claim} = StorageWork.claim(work.id, c.now)
    assert {:ok, completed} = StorageWork.finish(claim, {:ok, c.attrs.bytes}, c.now)
    assert Repo.get!(Acquisition, completed.acquisition_record_id).release_id

    assert {:error, :acquisition_conflict} =
             StorageWork.prepare(
               Map.put(attrs, :release, %{
                 fiscal_year_end: ~D[2026-03-31],
                 period: "q2",
                 category: "report"
               }),
               c.client
             )
  end

  test "poller finds persisted work without an in-memory queue", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)

    client = %{
      c.client
      | request: Req.new(plug: fn conn -> Plug.Conn.send_resp(conn, 200, c.attrs.bytes) end)
    }

    pid =
      start_supervised!(
        {Lens.Earnings.StorageRecovery, [name: nil, enabled: false, client: client]}
      )

    assert [{id, {:ok, %{status: "completed"}}}] = GenServer.call(pid, :poll)
    assert id == work.id
    assert [] = GenServer.call(pid, :poll)
  end

  test "ambiguous write failure keeps bytes and subsequent attempt reuses saved object", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    {:ok, state} = Agent.start_link(fn -> false end)

    client = %{
      c.client
      | request:
          Req.new(
            plug: fn conn ->
              case conn.method do
                "GET" ->
                  Plug.Conn.send_resp(
                    conn,
                    if(Agent.get(state, & &1), do: 200, else: 404),
                    c.attrs.bytes
                  )

                "PUT" ->
                  Agent.update(state, fn _ -> true end)
                  raise "connection closed after server saved object"
              end
            end
          )
    }

    assert {:ok, pending} = StorageWork.recover(work.id, client, c.now)
    assert pending.last_failure == "transport_error"
    assert pending.bytes == c.attrs.bytes

    assert {:ok, %{status: "completed"}} =
             StorageWork.recover(work.id, client, pending.next_attempt_at)
  end

  test "enabled poller automatically discovers committed work after start", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    owner = self()

    client = %{
      c.client
      | request:
          Req.new(
            plug: fn conn ->
              send(owner, :object_checked)
              Plug.Conn.send_resp(conn, 200, c.attrs.bytes)
            end
          )
    }

    pid =
      start_supervised!(
        {Lens.Earnings.StorageRecovery, [name: nil, enabled: true, client: client]}
      )

    assert_receive :object_checked, 3000
    assert [] = GenServer.call(pid, :poll)
    assert Repo.get!(StorageWork, work.id).status == "completed"
  end

  test "missing configuration requires operator attention and does not release payload", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    assert [{id, {:ok, failed}}] = StorageWork.recover_due({:error, :not_configured})
    assert id == work.id
    assert failed.status == "attention"
    assert failed.last_failure == "not_configured"
    assert failed.bytes == c.attrs.bytes
  end

  test "expired manual claim is audited as failed and never starts another attempt", c do
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    {:ok, claim} = StorageWork.claim(work.id, c.now)
    {:ok, _} = StorageWork.finish(claim, {:error, :unauthorized}, c.now)
    {:ok, _} = StorageWork.manual_retry(work.id, "operator", c.now)
    {:ok, manual} = StorageWork.claim(work.id, c.now)
    later = DateTime.add(c.now, 120, :second)
    assert {:error, :not_eligible} = StorageWork.claim(work.id, later)
    assert Repo.get!(StorageWork, work.id).attempts == 1
    assert Repo.get!(StorageWork, work.id).manual_attempts == 1
    assert [%{status: "failed", failure: "lease_expired"}] = StorageWork.audit(work.id)
    assert {:error, :stale_claim} = StorageWork.finish(manual, {:ok, c.attrs.bytes}, later)
  end

  test "unfinished metadata supports bounded pagination without returning payloads", c do
    {:ok, first} = StorageWork.prepare(c.attrs, c.client)
    {:ok, second} = StorageWork.prepare(%{c.attrs | acquisition_id: "work-2"}, c.client)
    assert [%{id: first_id} = metadata] = StorageWork.unfinished(1, 0)
    assert first_id == first.id
    refute Map.has_key?(metadata, :bytes)
    assert [%{id: second_id}] = StorageWork.unfinished(1, 1)
    assert second_id == second.id
    assert [] = StorageWork.unfinished(1, 2)
  end

  test "permanent storage rejection needs attention and records only sanitized failure codes",
       c do
    for {reason, index} <-
          Enum.with_index([
            :unauthorized,
            :invalid_configuration,
            :not_configured,
            :integrity_error,
            :not_found,
            {:http_error, 400},
            {:http_error, 301}
          ]) do
      {:ok, work} =
        StorageWork.prepare(%{c.attrs | acquisition_id: "permanent-#{index}"}, c.client)

      {:ok, claim} = StorageWork.claim(work.id, c.now)

      assert {:ok, %{status: "attention", attempts: 1}} =
               StorageWork.finish(claim, {:error, reason}, c.now)
    end
  end

  test "preparation rejects acquisition IDs already bound to conflicting observations", c do
    assert {:ok, _} =
             Lens.Earnings.record_success(%{c.attrs | url: "https://other.test/original"})

    assert {:error, :acquisition_conflict} = StorageWork.prepare(c.attrs, c.client)
    assert Repo.aggregate(StorageWork, :count) == 0
  end

  test "matching legacy observation can acquire a durable storage reference", c do
    {:ok, original} = Lens.Earnings.record_success(c.attrs)
    {:ok, work} = StorageWork.prepare(c.attrs, c.client)
    {:ok, claim} = StorageWork.claim(work.id, c.now)
    assert {:ok, completed} = StorageWork.finish(claim, {:ok, c.attrs.bytes}, c.now)
    assert completed.acquisition_record_id == original.acquisition.id
    assert Repo.aggregate(Acquisition, :count) == 1
  end
end
