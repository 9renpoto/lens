defmodule Lens.Earnings.RunBudget do
  @moduledoc "Sequential HTTP acquisition budgets shared across one collection run."
  alias Lens.Earnings.HTTP

  defstruct [:deadline, :max_requests, :max_operations, requests: 0, operations: 0]

  def new(options \\ []) do
    requests = Keyword.get(options, :max_requests, 24)
    operations = Keyword.get(options, :max_operations, 8)
    timeout = Keyword.get(options, :timeout_ms, 120_000)

    if is_integer(requests) and requests in 1..32 and is_integer(operations) and
         operations in 1..16 and is_integer(timeout) and timeout in 1..300_000 do
      {:ok,
       %__MODULE__{
         deadline: now() + timeout,
         max_requests: requests,
         max_operations: operations
       }}
    else
      {:error, :invalid_budget}
    end
  end

  def fetch(%__MODULE__{} = budget, url, options \\ []) do
    remaining = budget.deadline - now()
    timeout = Keyword.get(options, :timeout_ms, 20_000)
    redirects = Keyword.get(options, :max_redirects, 3)

    cond do
      budget.requests >= budget.max_requests ->
        {:error, :request_budget_exhausted, budget}

      budget.operations >= budget.max_operations ->
        {:error, :operation_budget_exhausted, budget}

      remaining <= 0 ->
        {:error, :run_deadline_exceeded, budget}

      not is_integer(timeout) or timeout not in 1..30_000 or
        not is_integer(redirects) or redirects not in 0..3 ->
        {:error, :invalid_options, budget}

      true ->
        deadline =
          case Keyword.get(options, :deadline) do
            nil ->
              budget.deadline

            caller_deadline when is_integer(caller_deadline) ->
              min(caller_deadline, budget.deadline)

            invalid_deadline ->
              invalid_deadline
          end

        options =
          options
          |> Keyword.put(:deadline, deadline)
          |> Keyword.put(:timeout_ms, min(timeout, remaining))
          |> Keyword.put(
            :max_redirects,
            min(redirects, budget.max_requests - budget.requests - 1)
          )

        result = HTTP.fetch(url, options)

        {:ok, result,
         %{
           budget
           | requests: budget.requests + result.requests,
             operations: budget.operations + 1
         }}
    end
  end

  @doc "Return a bounded delay for retry indices 0 and 1; defer unsupported or long Retry-After values."
  def retry_delay(%{retryable: false}, _), do: {:error, :not_retryable}

  def retry_delay(%{retryable: true} = result, attempt) when attempt in [0, 1] do
    base = 1000 * (attempt + 1)

    case get_in(result, [:headers, "retry-after"]) do
      nil ->
        {:ok, base}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {seconds, ""} when seconds in 0..30 -> {:ok, max(base, seconds * 1000)}
          _ -> {:error, :defer_retry}
        end

      _ ->
        {:error, :defer_retry}
    end
  end

  def retry_delay(_, _), do: {:error, :retry_limit}

  defp now, do: System.monotonic_time(:millisecond)
end
