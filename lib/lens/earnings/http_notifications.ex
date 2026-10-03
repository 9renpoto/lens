defmodule Lens.Earnings.HTTPNotifications do
  @moduledoc false

  def worker_exit_reason(completed_at, deadline) do
    if completed_at >= deadline, do: :timeout, else: :transport_error
  end

  def drain_terminal(ref) do
    receive do
      {^ref, :result, completed_at, result} -> {:result, completed_at, result}
      {^ref, :worker_exit, completed_at} -> {:worker_exit, completed_at}
    after
      0 -> :none
    end
  end

  def drain_after_worker_stops(ref, url, requests) do
    case drain_terminal(ref) do
      {:result, completed_at, result} ->
        requests = max(result.requests, requests)
        {_url, requests} = drain(ref, result.final_url || url, requests)
        {:result, completed_at, result, requests}

      {:worker_exit, completed_at} ->
        {url, requests} = drain(ref, url, requests)
        {:worker_exit, completed_at, url, requests}

      :none ->
        {url, requests} = drain(ref, url, requests)
        {:none, url, requests}
    end
  end

  def drain(ref, url, requests) do
    receive do
      {^ref, kind, next_url, count} when kind in [:evaluating, :started] ->
        drain(ref, next_url, max(requests, count))

      {^ref, :result, _, result} ->
        drain(ref, result.final_url || url, max(requests, result.requests))
    after
      0 -> {url, requests}
    end
  end
end
