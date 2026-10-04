defmodule Lens.Earnings.HTTPNotifications do
  @moduledoc false

  def worker_exit_reason(completed_at, deadline) do
    if completed_at >= deadline, do: :timeout, else: :transport_error
  end

  def drain(ref, url, requests) do
    receive do
      {^ref, kind, next_url, count} when kind in [:evaluating, :started] ->
        drain(ref, next_url, max(requests, count))

      {^ref, :result, completed_at, result} ->
        {:result, completed_at, result, max(requests, result.requests)}

      {^ref, :worker_exit, completed_at} ->
        {:worker_exit, completed_at, url, requests}
    after
      0 -> {:none, url, requests}
    end
  end
end
