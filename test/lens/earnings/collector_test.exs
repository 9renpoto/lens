defmodule Lens.Earnings.CollectorTest do
  use Lens.DataCase
  alias Lens.Analysis
  alias Lens.Earnings.{Acquisition, Collector, HTTPCheck, Original, RustFS, Sources}

  setup do
    objects = start_supervised!({Agent, fn -> %{} end})

    {:ok, client} =
      RustFS.new(
        endpoint: "http://storage.test",
        bucket: "lens-test",
        access_key_id: "test",
        secret_access_key: "test"
      )

    client = %{
      client
      | request:
          Req.new(
            retry: false,
            plug: fn conn ->
              case conn.method do
                "PUT" ->
                  Agent.update(objects, &Map.put(&1, conn.request_path, Req.Test.raw_body(conn)))
                  Plug.Conn.send_resp(conn, 200, "")

                "GET" ->
                  case Agent.get(objects, &Map.get(&1, conn.request_path)) do
                    nil -> Plug.Conn.send_resp(conn, 404, "")
                    bytes -> Plug.Conn.send_resp(conn, 200, bytes)
                  end
              end
            end
          )
    }

    %{client: client}
  end

  test "acquires published external links without classifying and preserves disabled-source history",
       %{client: client} do
    pdf = server("%PDF-candidate", "/actual.pdf")
    listing = server(~s(<h2>Results</h2><a href="#{pdf}">Unknown document</a>), "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "A7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test",
        active: false
      })

    {:ok, source} = Sources.create(target, %{listing_url: listing})

    {:ok, disabled} =
      Sources.create(target, %{listing_url: "http://localhost:1/disabled", enabled: false})

    assert {:ok, run} = Collector.run(rustfs: client, allowed_url?: fn _ -> true end)
    assert run.budget.operations == 2
    assert [candidate] = Enum.filter(run.checks, &(&1.kind == "pdf"))
    assert candidate.metadata["source_id"] == source.id
    assert candidate.metadata["target_id"] == target.id
    assert candidate.metadata["listing_url"] == listing
    assert candidate.metadata["anchor_text"] == "Unknown document"
    assert candidate.metadata["listing_check_id"] == hd(run.checks).id
    assert candidate.metadata["observed_listing_url"] == listing
    acquisition = Repo.get!(Acquisition, candidate.acquisition_id)
    assert acquisition.issuer_code == "A7203"
    assert acquisition.release_id == nil

    assert Lens.Earnings.original_bytes(acquisition.original_id, rustfs: client) ==
             {:ok, "%PDF-candidate"}

    assert Enum.all?(run.checks, &(&1.metadata["source_id"] != disabled.id))

    {:ok, _} = Sources.update(source, %{enabled: false})
    assert {:ok, %{checks: [], budget: %{operations: 0}}} = Collector.run(rustfs: client)
    assert Repo.aggregate(HTTPCheck, :count) == 2
  end

  test "records failed PDFs and continues to other links under one run budget", %{client: client} do
    bad = server("not a PDF", "/bad.pdf")
    good = server("%PDF-good", "/good.pdf")
    listing = server(~s(<a href="#{bad}">Bad</a><a href="#{good}">Good</a>), "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, _} = Sources.create(target, %{listing_url: listing})
    assert {:ok, run} = Collector.run(rustfs: client, allowed_url?: fn _ -> true end)
    assert Enum.map(run.checks, & &1.status) == ["success", "failed", "success"]
    assert Enum.at(run.checks, 1).failure_reason == "non_pdf"
    assert Repo.aggregate(Acquisition, :count) == 2
  end

  test "uses the operation budget to collect the first candidate from a long listing", %{
    client: client
  } do
    first = server("%PDF-first", "/first.pdf")

    archived =
      Enum.map_join(1..200, fn index ->
        ~s(<a href="http://localhost:1/archive-#{index}.pdf">Archived #{index}</a>)
      end)

    listing = server(~s(<a href="#{first}">Newest</a>#{archived}), "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, _} = Sources.create(target, %{listing_url: listing})

    assert {:ok, run} =
             Collector.run(rustfs: client, allowed_url?: fn _ -> true end, max_operations: 2)

    assert run.errors == []
    assert run.stopped == nil
    assert run.budget.operations == 2
    assert Enum.map(run.checks, & &1.kind) == ["listing", "pdf"]
    assert [candidate] = Enum.filter(run.checks, &(&1.kind == "pdf"))
    assert candidate.metadata["anchor_text"] == "Newest"
    assert Repo.aggregate(Acquisition, :count) == 1
  end

  test "stops before another operation when the budget is exhausted", %{client: client} do
    listing = server(~s(<a href="https://external.invalid/report.pdf">Report</a>), "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, _} = Sources.create(target, %{listing_url: listing})

    assert {:ok, run} =
             Collector.run(rustfs: client, allowed_url?: fn _ -> true end, max_operations: 1)

    assert run.stopped == :operation_budget_exhausted
    assert length(run.checks) == 1
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "storage failure records the download failure and stops all sources without excluding later runs",
       %{
         client: client
       } do
    pdf = server("%PDF-pending", "/pending.pdf")
    later = server("%PDF-later", "/later.pdf")
    listing = server(~s(<a href="#{pdf}">First</a><a href="#{later}">Later</a>), "/results")
    good = server("<html>No PDFs</html>", "/other")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: listing})
    {:ok, other} = Sources.create(target, %{listing_url: good})
    owner = self()

    failing = %{
      client
      | request:
          Req.new(
            retry: false,
            plug: fn conn ->
              send(owner, :storage_request)
              Plug.Conn.send_resp(conn, 503, "")
            end
          )
    }

    assert {:ok, run} = Collector.run(rustfs: failing)
    assert run.stopped == :storage_failed
    assert run.budget.operations == 2
    assert run.errors == [%{source_id: source.id, reason: {:storage_failed, "unavailable"}}]
    assert Enum.all?(run.checks, &(&1.kind == "listing"))
    refute Enum.any?(run.checks, &(&1.metadata["source_id"] == other.id))
    assert_receive :storage_request
    refute_receive :storage_request

    assert [%{status: "failed", original_id: nil, failure_reason: "storage_unavailable"}] =
             Repo.all(Acquisition)

    assert Repo.aggregate(Original, :count) == 0

    assert {:ok, next} = Collector.run(rustfs: client)
    assert next.stopped == nil
    assert next.errors == []
    assert next.budget.operations == 4
    assert Enum.count(Repo.all(Acquisition), &(&1.status == "success")) == 2
    assert Repo.aggregate(Acquisition, :count) == 3
  end

  test "failure to persist completion rolls back the successful acquisition and stops all sources",
       %{
         client: client
       } do
    pdf = server("%PDF-completion", "/report.pdf")
    listing = server(~s(<a href="#{pdf}">Report</a>), "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: listing})
    {:ok, _} = Sources.create(target, %{listing_url: "http://localhost:1/later"})

    Repo.query!("""
    CREATE FUNCTION pg_temp.reject_pdf_check() RETURNS trigger AS $$
    BEGIN
      IF NEW.kind = 'pdf' THEN
        RAISE EXCEPTION 'test completion rejected'
          USING ERRCODE = '23514', CONSTRAINT = 'earnings_http_check_acquisition_facts';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!(
      "CREATE TRIGGER reject_pdf_check BEFORE INSERT ON earnings_http_checks FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_pdf_check()"
    )

    assert {:ok, run} = Collector.run(rustfs: client)
    assert run.stopped == :persistence_failed
    assert run.budget.operations == 2
    assert [%{source_id: source_id, reason: %Ecto.Changeset{}}] = run.errors
    assert source_id == source.id
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
    assert [%{kind: "listing"}] = Repo.all(HTTPCheck)
  end

  test "missing storage configuration performs no publisher requests" do
    previous = Application.get_env(:lens, RustFS)
    Application.delete_env(:lens, RustFS)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lens, RustFS, previous),
        else: Application.delete_env(:lens, RustFS)
    end)

    assert Collector.run() == {:error, :not_configured}
    assert Repo.aggregate(HTTPCheck, :count) == 0
  end

  defp server(body, path) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    pid = spawn(fn -> serve(listener, body) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    host = if String.ends_with?(path, ".pdf"), do: "localhost", else: "127.0.0.1"
    "http://#{host}:#{port}#{path}"
  end

  test "rejects a redirect through the URL policy and keeps other sources running", %{
    client: client
  } do
    blocked = "http://localhost:1/private.pdf"
    redirect = server({302, [{"Location", blocked}], ""}, "/results")
    good = server("<html>No PDFs</html>", "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, _} = Sources.create(target, %{listing_url: redirect})
    {:ok, _} = Sources.create(target, %{listing_url: good})
    assert {:ok, run} = Collector.run(rustfs: client, allowed_url?: &(&1 != blocked))

    assert Enum.any?(
             run.checks,
             &(&1.failure_reason == "url_not_allowed" and &1.final_url == blocked)
           )

    assert Enum.any?(run.checks, &(&1.status == "success"))
    assert run.budget.requests == 2
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "default policy rejects credentials without sending a request", %{client: client} do
    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    listing =
      server(~s(<a href="http://user:secret@localhost:1/report.pdf">Unsafe</a>), "/results")

    {:ok, _} = Sources.create(target, %{listing_url: listing})
    assert {:ok, run} = Collector.run(rustfs: client)
    assert length(run.checks) == 1
    assert run.budget.requests == 1
  end

  test "invalid budgets perform no acquisition" do
    assert Collector.run(max_operations: 0) == {:error, :invalid_budget}
    assert Repo.aggregate(HTTPCheck, :count) == 0
  end

  test "an invalid listing remains recorded while another source continues", %{client: client} do
    invalid = server(<<255>>, "/results")
    good = server("<html>No PDFs</html>", "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, bad_source} = Sources.create(target, %{listing_url: invalid})
    {:ok, good_source} = Sources.create(target, %{listing_url: good})

    assert {:ok, run} = Collector.run(rustfs: client)
    assert run.stopped == nil
    assert run.errors == [%{source_id: bad_source.id, reason: :invalid_html}]
    assert length(run.checks) == 2
    assert Enum.any?(run.checks, &(&1.metadata["source_id"] == good_source.id))
    assert Repo.aggregate(HTTPCheck, :count) == 2
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "candidate persistence failure stops before fetching another link or source", %{
    client: client
  } do
    pdf = server("%PDF-candidate", "/report.pdf")

    listing =
      server(
        ~s(<a href="#{pdf}">#{String.duplicate("x", 33_000)}</a><a href="http://localhost:1/later.pdf">Later</a>),
        "/results"
      )

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: listing})

    {:ok, later_target} =
      Analysis.create_target(%{
        security_code: "9999",
        market: "TSE",
        display_name: "Later",
        sector: "Test"
      })

    {:ok, _} = Sources.create(later_target, %{listing_url: "http://localhost:1/later"})

    assert {:ok, run} = Collector.run(rustfs: client)
    assert run.stopped == :persistence_failed
    assert run.budget.operations == 2
    assert [%{source_id: source_id, reason: %Ecto.Changeset{} = reason}] = run.errors
    assert source_id == source.id
    assert errors_on(reason).metadata != []
    assert length(run.checks) == 1
    assert Repo.aggregate(HTTPCheck, :count) == 1
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Lens.Earnings.Original, :count) == 0
  end

  defp serve(listener, body) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        :gen_tcp.recv(socket, 0, 2000)

        {status, headers, bytes} =
          case body do
            {status, headers, bytes} -> {status, headers, bytes}
            bytes -> {200, [], bytes}
          end

        headers = Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end)

        :gen_tcp.send(socket, [
          "HTTP/1.1 #{status} Response\r\n",
          headers,
          "Content-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n",
          bytes
        ])

        :gen_tcp.close(socket)
        serve(listener, body)

      _ ->
        :ok
    end
  end
end
