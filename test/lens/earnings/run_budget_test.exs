defmodule Lens.Earnings.RunBudgetTest do
  use ExUnit.Case, async: true
  alias Lens.Earnings.RunBudget

  test "redirect hops share one request budget and exhaustion sends no later request" do
    owner = self()

    url =
      server(
        fn socket, _ ->
          send(owner, :requested)
          respond(socket, 302, "", [{"Location", "/next"}])
        end,
        3
      )

    assert {:ok, budget} = RunBudget.new(max_requests: 2)
    assert {:ok, result, budget} = RunBudget.fetch(budget, url, allowed_url?: allow(url))
    assert result.requests == 2
    assert result.failure_reason == :redirect_limit
    assert budget.requests == 2

    assert {:error, :request_budget_exhausted, ^budget} =
             RunBudget.fetch(budget, url, allowed_url?: allow(url))

    assert_receive :requested
    assert_receive :requested
    refute_receive :requested, 30
  end

  test "pre-request rejection consumes an operation but no HTTP request" do
    assert {:ok, budget} = RunBudget.new(max_operations: 1)
    assert {:ok, result, budget} = RunBudget.fetch(budget, "https://example.test/file.pdf")
    assert result.requests == 0
    assert budget.requests == 0

    assert {:error, :operation_budget_exhausted, ^budget} =
             RunBudget.fetch(budget, "https://example.test/file.pdf")
  end

  test "an expired run does not begin acquisition" do
    assert {:ok, budget} = RunBudget.new(timeout_ms: 1)
    Process.sleep(3)

    assert {:error, :run_deadline_exceeded, ^budget} =
             RunBudget.fetch(budget, "https://example.test/file.pdf")
  end

  test "slow policy evaluation cannot extend the run or start a late request" do
    owner = self()

    url =
      server(fn socket, _ ->
        send(owner, :late_request)
        respond(socket, 200, "%PDF-late")
      end)

    {:ok, counter} = Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)

    policy = fn _ ->
      count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
      if count == 0, do: Process.sleep(200)
      true
    end

    assert {:ok, budget} = RunBudget.new(timeout_ms: 30)
    started = System.monotonic_time(:millisecond)
    assert {:ok, result, updated} = RunBudget.fetch(budget, url, allowed_url?: policy)
    assert result.failure_reason == :timeout
    assert result.requests == 0
    assert updated.requests == 0
    assert System.monotonic_time(:millisecond) - started < 150
    refute_receive :late_request, 50
  end

  test "a slow operation cannot outlive the remaining run deadline" do
    url =
      server(fn socket, _ ->
        Process.sleep(150)
        respond(socket, 200, "%PDF-slow")
      end)

    assert {:ok, budget} = RunBudget.new(timeout_ms: 30)

    assert {:ok, result, budget} =
             RunBudget.fetch(budget, url, allowed_url?: allow(url), timeout_ms: 1000)

    assert result.failure_reason == :timeout
    assert budget.requests == 1

    assert {:error, :run_deadline_exceeded, _} =
             RunBudget.fetch(budget, url, allowed_url?: allow(url))
  end

  test "retry delay is capped by attempts and respects publisher Retry-After" do
    result = %{retryable: true, headers: %{}}
    assert {:ok, 1000} = RunBudget.retry_delay(result, 0)
    assert {:ok, 2000} = RunBudget.retry_delay(result, 1)
    assert {:error, :retry_limit} = RunBudget.retry_delay(result, 2)

    assert {:error, :defer_retry} =
             RunBudget.retry_delay(%{result | headers: %{"retry-after" => ["5"]}}, 0)

    assert {:error, :not_retryable} = RunBudget.retry_delay(%{retryable: false}, 0)
    assert {:ok, 5000} = RunBudget.retry_delay(%{result | headers: %{"retry-after" => "5"}}, 0)

    assert {:error, :defer_retry} =
             RunBudget.retry_delay(%{result | headers: %{"retry-after" => "3600"}}, 0)

    assert {:error, :defer_retry} =
             RunBudget.retry_delay(
               %{result | headers: %{"retry-after" => "Wed, 21 Oct 2026 07:28:00 GMT"}},
               0
             )
  end

  test "invalid budget bounds and transport options do not start requests" do
    for opts <- [
          [max_requests: 0],
          [max_requests: 33],
          [max_operations: 17],
          [timeout_ms: 300_001]
        ] do
      assert {:error, :invalid_budget} = RunBudget.new(opts)
    end

    assert {:ok, budget} = RunBudget.new()

    for opts <- [[timeout_ms: 0], [max_redirects: 4]] do
      assert {:error, :invalid_options, ^budget} =
               RunBudget.fetch(budget, "https://example.test/file.pdf", opts)
    end
  end

  defp allow(url) do
    base = URI.parse(url)

    fn candidate ->
      uri = URI.parse(candidate)
      {uri.scheme, uri.host, uri.port} == {base.scheme, base.host, base.port}
    end
  end

  defp respond(socket, status, body, headers \\ []) do
    headers = [{"Content-Length", to_string(byte_size(body))}, {"Connection", "close"} | headers]

    :gen_tcp.send(socket, [
      "HTTP/1.1 #{status} OK\r\n",
      Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end),
      "\r\n",
      body
    ])
  end

  defp server(handler, count \\ 1) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        for _ <- 1..count do
          case :gen_tcp.accept(listener, 1000) do
            {:ok, socket} ->
              case :gen_tcp.recv(socket, 0, 1000) do
                {:ok, request} -> handler.(socket, request)
                _ -> :ok
              end

              :gen_tcp.close(socket)

            _ ->
              :ok
          end
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    "http://127.0.0.1:#{port}/"
  end
end
