defmodule Lens.Earnings.CollectorTest do
  use Lens.DataCase
  alias Lens.Analysis
  alias Lens.Earnings.{Acquisition, Collector, HTTPCheck, Sources}

  test "acquires published external links without classifying and preserves disabled-source history" do
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

    assert {:ok, run} = Collector.run(allowed_url?: fn _ -> true end)
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
    assert Lens.Earnings.original_bytes(acquisition.original_id) == {:ok, "%PDF-candidate"}
    assert Enum.all?(run.checks, &(&1.metadata["source_id"] != disabled.id))

    {:ok, _} = Sources.update(source, %{enabled: false})
    assert {:ok, %{checks: [], budget: %{operations: 0}}} = Collector.run()
    assert Repo.aggregate(HTTPCheck, :count) == 2
  end

  test "records failed PDFs and continues to other links under one run budget" do
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
    assert {:ok, run} = Collector.run(allowed_url?: fn _ -> true end)
    assert Enum.map(run.checks, & &1.status) == ["success", "failed", "success"]
    assert Enum.at(run.checks, 1).failure_reason == "non_pdf"
    assert Repo.aggregate(Acquisition, :count) == 2
  end

  test "stops before another operation when the budget is exhausted" do
    listing = server(~s(<a href="https://external.invalid/report.pdf">Report</a>), "/results")

    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, _} = Sources.create(target, %{listing_url: listing})
    assert {:ok, run} = Collector.run(allowed_url?: fn _ -> true end, max_operations: 1)
    assert run.stopped == :operation_budget_exhausted
    assert length(run.checks) == 1
    assert Repo.aggregate(Acquisition, :count) == 0
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

  test "rejects a redirect through the URL policy and keeps other sources running" do
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
    assert {:ok, run} = Collector.run(allowed_url?: &(&1 != blocked))

    assert Enum.any?(
             run.checks,
             &(&1.failure_reason == "url_not_allowed" and &1.final_url == blocked)
           )

    assert Enum.any?(run.checks, &(&1.status == "success"))
    assert run.budget.requests == 2
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "default policy rejects credentials without sending a request" do
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
    assert {:ok, run} = Collector.run()
    assert length(run.checks) == 1
    assert run.budget.requests == 1
  end

  test "invalid budgets perform no acquisition" do
    assert Collector.run(max_operations: 0) == {:error, :invalid_budget}
    assert Repo.aggregate(HTTPCheck, :count) == 0
  end

  test "an invalid listing remains recorded while another source continues" do
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

    assert {:ok, run} = Collector.run()
    assert run.stopped == nil
    assert run.errors == [%{source_id: bad_source.id, reason: :invalid_html}]
    assert length(run.checks) == 2
    assert Enum.any?(run.checks, &(&1.metadata["source_id"] == good_source.id))
    assert Repo.aggregate(HTTPCheck, :count) == 2
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "candidate persistence failure stops before fetching another link or source" do
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

    assert {:ok, run} = Collector.run()
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
