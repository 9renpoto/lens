defmodule Lens.Earnings.HTTP do
  @moduledoc "Streaming HTTP acquisition with one total deadline and explicit URL policy."

  @redirects [301, 302, 303, 307, 308]

  def fetch(url, options \\ []) do
    started = now()
    kind = Keyword.get(options, :kind, :pdf)

    limit =
      Keyword.get(options, :max_bytes, if(kind == :listing, do: 2_097_152, else: 20_971_520))

    timeout = Keyword.get(options, :timeout_ms, 20_000)
    redirects = Keyword.get(options, :max_redirects, 3)
    policy = Keyword.get(options, :allowed_url?, fn _ -> false end)
    requested_deadline = Keyword.get(options, :deadline)

    cond do
      kind not in [:pdf, :listing] or not is_integer(limit) or limit < 1 or
        limit > if(kind == :listing, do: 2_097_152, else: 20_971_520) or
        not is_integer(timeout) or timeout not in 1..30_000 or
        not is_integer(redirects) or redirects not in 0..3 or not is_function(policy, 1) or
          (requested_deadline != nil and not is_integer(requested_deadline)) ->
        failure(:invalid_options, url, 0)

      true ->
        bounded(url, %{
          kind: kind,
          limit: limit,
          deadline: min(started + timeout, requested_deadline || started + timeout),
          redirects: redirects,
          policy: policy,
          headers: Keyword.get(options, :headers, [])
        })
    end
  end

  defp bounded(url, config) do
    owner = self()
    ref = make_ref()
    deadline = config.deadline

    {worker, monitor} =
      spawn_monitor(fn ->
        worker = self()
        spawn(fn -> guard(owner, worker) end)
        result = request(url, config, deadline, 0, owner, ref)
        send(owner, {ref, :result, result})
      end)

    await(worker, monitor, ref, deadline, url, 0)
  end

  defp guard(owner, worker) do
    owner_ref = Process.monitor(owner)
    worker_ref = Process.monitor(worker)

    receive do
      {:DOWN, ^owner_ref, :process, _, _} -> Process.exit(worker, :kill)
      {:DOWN, ^worker_ref, :process, _, _} -> :ok
    end
  end

  defp await(worker, monitor, ref, deadline, url, requests) do
    receive do
      {^ref, :started, next_url, count} ->
        await(worker, monitor, ref, deadline, next_url, count)

      {^ref, :result, result} ->
        Process.demonitor(monitor, [:flush])
        %{result | requests: max(result.requests, requests)}

      {:DOWN, ^monitor, :process, _, _} ->
        failure(:transport_error, url, requests)
    after
      max(deadline - now(), 0) ->
        Process.exit(worker, :kill)

        receive do
          {:DOWN, ^monitor, :process, _, _} -> :ok
        end

        drain(ref)
        failure(:timeout, url, requests)
    end
  end

  defp drain(ref) do
    receive do
      {^ref, _, _, _} -> drain(ref)
      {^ref, :result, _} -> drain(ref)
    after
      0 -> :ok
    end
  end

  defp request(url, config, deadline, count, owner, ref) do
    cond do
      now() >= deadline ->
        failure(:timeout, url, count)

      not allowed?(url, config.policy) ->
        failure(:url_not_allowed, url, count)

      now() >= deadline ->
        failure(:timeout, url, count)

      true ->
        count = count + 1
        send(owner, {ref, :started, url, count})
        remaining = max(deadline - now(), 1)

        response =
          Req.get(url,
            headers: [{"accept-encoding", "identity"} | config.headers],
            compressed: false,
            raw: true,
            redirect: false,
            retry: false,
            receive_timeout: remaining,
            connect_options: [timeout: 30_000],
            into: fn {:data, chunk}, {req, resp} -> stream(req, resp, chunk, config.limit) end
          )

        finish(response, url, config, deadline, count, owner, ref)
    end
  rescue
    _ -> failure(:transport_error, url, count)
  end

  defp stream(req, resp, chunk, limit) do
    size = Map.get(resp.private, :lens_size, 0) + byte_size(chunk)

    reason =
      cond do
        resp.status != 200 -> nil
        oversized?(resp.headers, limit) or size > limit -> :too_large
        encoded?(resp.headers) -> :unsupported_encoding
        true -> nil
      end

    if resp.status != 200 or reason do
      {:halt, {req, %{resp | private: Map.put(resp.private, :lens_failure, reason)}}}
    else
      private =
        resp.private
        |> Map.put(:lens_size, size)
        |> Map.update(:lens_chunks, [chunk], &[chunk | &1])

      {:cont, {req, %{resp | private: private}}}
    end
  end

  defp finish({:ok, resp}, url, config, deadline, count, owner, ref) do
    base = %{
      failure(:http_error, url, count)
      | headers: headers(resp.headers),
        http_status: resp.status
    }

    cond do
      resp.status == 304 ->
        %{base | outcome: :not_modified, failure_reason: nil, retryable: false}

      resp.status in @redirects ->
        redirect(base, config, deadline, count, owner, ref)

      resp.status != 200 ->
        %{base | retryable: resp.status == 429 or resp.status >= 500}

      reason = Map.get(resp.private, :lens_failure) ->
        %{base | failure_reason: reason, retryable: false}

      oversized?(resp.headers, config.limit) ->
        %{base | failure_reason: :too_large, retryable: false}

      encoded?(resp.headers) ->
        %{base | failure_reason: :unsupported_encoding, retryable: false}

      true ->
        bytes =
          resp.private |> Map.get(:lens_chunks, []) |> Enum.reverse() |> IO.iodata_to_binary()

        if config.kind == :pdf and not String.starts_with?(bytes, "%PDF-") do
          %{base | failure_reason: :non_pdf, retryable: false}
        else
          %{base | outcome: :success, failure_reason: nil, bytes: bytes, retryable: false}
        end
    end
  end

  defp finish({:error, error}, url, _config, _deadline, count, _owner, _ref) do
    reason =
      case Map.get(error, :reason) do
        :timeout -> :timeout
        :closed -> :interrupted
        _ -> :transport_error
      end

    failure(reason, url, count)
  end

  defp redirect(base, config, deadline, count, owner, ref) do
    location = Map.get(base.headers, "location")

    cond do
      count > config.redirects ->
        %{base | failure_reason: :redirect_limit, retryable: false}

      not is_binary(location) ->
        %{base | failure_reason: :invalid_redirect, retryable: false}

      true ->
        case URI.new(location) do
          {:ok, reference} ->
            target = base.final_url |> URI.merge(reference) |> URI.to_string()

            request(
              target,
              redirect_config(config, base.final_url, target),
              deadline,
              count,
              owner,
              ref
            )

          {:error, _} ->
            %{base | failure_reason: :invalid_redirect, retryable: false}
        end
    end
  end

  defp redirect_config(config, from, to) do
    if origin(from) == origin(to) do
      config
    else
      headers =
        Enum.filter(config.headers, fn {name, _} ->
          String.downcase(to_string(name)) in ["accept", "accept-language", "user-agent"]
        end)

      %{config | headers: headers}
    end
  end

  defp origin(url) do
    uri = URI.parse(url)
    {String.downcase(uri.scheme), String.downcase(uri.host), uri.port}
  end

  defp allowed?(url, policy) when is_binary(url) do
    case URI.new(url) do
      {:ok, %{scheme: scheme, host: host, userinfo: nil}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        policy.(url) == true

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp allowed?(_, _), do: false

  defp oversized?(headers, limit) do
    case Integer.parse(Map.get(headers(headers), "content-length", "")) do
      {size, ""} -> size > limit
      _ -> false
    end
  end

  defp encoded?(values) do
    case Map.get(headers(values), "content-encoding", "identity") do
      value when is_binary(value) -> String.downcase(String.trim(value)) != "identity"
      _ -> true
    end
  end

  defp headers(values),
    do:
      Map.new(values, fn {key, values} ->
        {String.downcase(key), if(is_list(values), do: List.first(values), else: values)}
      end)

  defp failure(reason, url, count),
    do: %{
      outcome: :failed,
      failure_reason: reason,
      final_url: url,
      requests: count,
      http_status: nil,
      headers: %{},
      bytes: nil,
      retryable: reason in [:timeout, :interrupted, :transport_error]
    }

  defp now, do: System.monotonic_time(:millisecond)
end
