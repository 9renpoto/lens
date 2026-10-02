defmodule Lens.Earnings.HTTPNotifications do
  @moduledoc false

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
