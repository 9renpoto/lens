defmodule Lens.Ingestion.Materials do
  @moduledoc "Acquires item-associated material without HTML originals, release inference or replay."
  alias Lens.{Content, Earnings, ErrorReporter, Repo}
  alias Lens.Earnings.{HTTP, RustFS}
  alias Lens.Ingestion.{HTMLMaterial, Material}

  @unsupported ~w(.xls .xlsx .xbrl .zip .doc .docx .csv)

  @doc "Acquire a feed batch under one deadline without a replay queue."
  def acquire_many(signals, options \\ []) do
    options = Keyword.put(options, :deadline, System.monotonic_time(:millisecond) + 30_000)

    Enum.reduce(signals, %{materials: [], errors: []}, fn signal, acc ->
      result = acquire(signal, options)
      %{materials: acc.materials ++ result.materials, errors: acc.errors ++ result.errors}
    end)
  end

  @spec acquire(map(), keyword()) :: %{materials: [Material.t()], errors: [map()]}
  def acquire(signal, options \\ []) do
    source = Content.get_source!(signal.source_id)
    timeout = Keyword.get(options, :timeout_ms, 30_000)
    maximum = Keyword.get(options, :max_materials, 8)

    with true <- source.enabled and source.ingestion_mode == "earnings_updates",
         true <-
           is_integer(timeout) and timeout in 1..30_000 and is_integer(maximum) and
             maximum in 1..16,
         {:ok, policy} <- policy(source.acquisition_metadata) do
      entry_url = Map.get(signal.entry, :entry_url) || signal.entry.canonical_url

      initial =
        if entry_url,
          do: [
            {entry_url, :auto,
             %{"relation" => "feed_item", "anchor_text" => Map.get(signal.entry, :title)}}
          ],
          else: []

      {attachments, errors} =
        references(
          Map.get(signal.entry, :attachments, []),
          Map.get(signal.entry, :body_links, [])
        )

      state = %{
        pending: initial ++ attachments,
        seen: MapSet.new(),
        materials: [],
        errors: errors,
        deadline:
          min(
            System.monotonic_time(:millisecond) + timeout,
            Keyword.get(options, :deadline, System.monotonic_time(:millisecond) + timeout)
          ),
        maximum: maximum
      }

      state =
        if state.pending == [],
          do: error(state, :association, :missing_material_reference),
          else: state

      state = run(state, source, signal, policy, options)
      %{materials: Enum.reverse(state.materials), errors: Enum.reverse(state.errors)}
    else
      false -> failure(:acquisition, :invalid_acquisition_configuration)
      {:error, reason} -> failure(:acquisition, reason)
    end
  rescue
    error ->
      ErrorReporter.report(:acquisition, error)
      %{materials: [], errors: [%{stage: :acquisition, reason: :processing_failed}]}
  end

  defp run(%{pending: []} = state, _, _, _, _), do: state

  defp run(state, source, signal, policy, options) do
    [{url, hint, provenance} | pending] = state.pending
    state = %{state | pending: pending}
    key = strip_fragment(url)

    cond do
      MapSet.member?(state.seen, key) ->
        run(state, source, signal, policy, options)

      MapSet.size(state.seen) >= state.maximum ->
        error(%{state | pending: []}, :acquisition, :too_many_materials)

      true ->
        state = %{state | seen: MapSet.put(state.seen, key)}

        fetch_options =
          options
          |> Keyword.take([:timeout_ms, :max_bytes, :max_redirects])
          |> Keyword.merge(
            kind: if(hint == :pdf, do: :pdf, else: :material),
            deadline: state.deadline,
            allowed_url?: policy
          )

        result = HTTP.fetch(key, fetch_options)

        state =
          case result do
            %{outcome: :success} ->
              handle(result, url, hint, provenance, state, source, signal, options)

            %{outcome: :not_modified} ->
              error(state, :acquisition, :unexpected_not_modified)

            %{failure_reason: reason} ->
              error(state, :acquisition, reason)
          end

        run(state, source, signal, policy, options)
    end
  end

  defp handle(result, url, hint, provenance, state, source, signal, options) do
    case media_kind(result, hint) do
      :pdf ->
        case save_pdf(result, url, provenance, source, signal, options, state.deadline) do
          {:ok, material} -> %{state | materials: [material | state.materials]}
          {:error, reason} -> error(state, :acquisition, reason)
        end

      :html ->
        case HTMLMaterial.parse(
               result.bytes,
               result.final_url,
               signal.entry,
               source.acquisition_metadata
             ) do
          {:ok, body} ->
            case save_html(result, url, body, source, signal) do
              {:ok, material} ->
                refs =
                  Enum.map(
                    body.provenance["links"],
                    &%{url: &1["url"], type: &1["type"], provenance: &1}
                  )

                {links, errors} = references(refs, [])

                %{
                  state
                  | materials: [material | state.materials],
                    pending: state.pending ++ links,
                    errors: errors ++ state.errors
                }

              {:error, _} ->
                error(state, :acquisition, :persistence_failed)
            end

          {:error, :ambiguous_material} ->
            error(state, :association, :ambiguous_material)

          {:error, reason} ->
            error(state, :extraction, reason)
        end

      :too_large ->
        error(state, :acquisition, :too_large)

      :unsupported ->
        error(state, :acquisition, :unsupported_format)
    end
  end

  defp save_html(result, url, body, source, signal) do
    attrs = attributes(result, url, source, signal)

    Material.changeset(
      Map.merge(attrs, %{
        kind: "html",
        text: body.text,
        content_hash: digest(body.text),
        provenance: body.provenance
      })
    )
    |> Repo.insert()
  end

  defp save_pdf(result, url, provenance, source, signal, options, deadline) do
    with {:ok, client} <- storage_client(options),
         remaining when remaining >= 2 <- deadline - System.monotonic_time(:millisecond),
         client <- %{client | timeout_ms: min(client.timeout_ms, div(remaining, 2))},
         {:ok, reference} <- RustFS.put(client, result.bytes) do
      reference = Map.merge(reference, %{endpoint: client.endpoint, bucket: client.bucket})

      Repo.transaction(fn ->
        with {:ok, original} <- Earnings.retain_original(result.bytes, reference),
             attrs <-
               Map.merge(attributes(result, url, source, signal), %{
                 kind: "pdf",
                 original_id: original.id,
                 content_hash: original.sha256,
                 provenance: provenance
               }),
             {:ok, material} <- Material.changeset(attrs) |> Repo.insert() do
          material
        else
          {:error, reason} when is_atom(reason) -> Repo.rollback(reason)
          _ -> Repo.rollback(:persistence_failed)
        end
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :timeout}
    end
  end

  defp attributes(result, url, source, signal) do
    %{
      source_id: source.id,
      item_key: signal.item_key,
      feed_fingerprint: signal.entry.feed_fingerprint,
      requested_url: url,
      final_url: result.final_url,
      acquired_at: DateTime.utc_now(),
      http_status: result.http_status,
      requests: result.requests,
      byte_size: byte_size(result.bytes),
      source_snapshot:
        Map.take(source, [
          :feed_format,
          :acquisition_kind,
          :publisher_authority,
          :endpoint_url,
          :original_feed_url
        ])
        |> json_map(),
      entry_snapshot:
        Map.take(signal.entry, [
          :source_entry_id,
          :title,
          :entry_url,
          :canonical_url,
          :published_at,
          :updated_at
        ])
        |> json_map()
    }
  end

  defp media_kind(result, hint) do
    type =
      result.headers
      |> Map.get("content-type", "")
      |> String.downcase()
      |> String.split(";")
      |> hd()
      |> String.trim()

    cond do
      String.starts_with?(result.bytes, "%PDF-") -> :pdf
      hint == :pdf or type not in ["", "text/html", "application/xhtml+xml"] -> :unsupported
      byte_size(result.bytes) > 2_097_152 -> :too_large
      true -> :html
    end
  end

  defp references(attachments, body_links) do
    candidates = attachments ++ Enum.map(body_links, &%{url: &1, type: nil})

    Enum.reduce(candidates, {[], []}, fn ref, {refs, errors} ->
      url = ref.url
      path = URI.parse(url).path || ""
      type = Map.get(ref, :type)
      provenance = Map.get(ref, :provenance, %{"relation" => "feed_reference"})

      cond do
        type == "application/pdf" or String.ends_with?(String.downcase(path), ".pdf") ->
          {refs ++ [{url, :pdf, provenance}], errors}

        type not in [nil, "", "text/html", "application/xhtml+xml"] or
            String.downcase(Path.extname(path)) in @unsupported ->
          ErrorReporter.report(:acquisition, :unsupported_format)
          {refs, [%{stage: :acquisition, reason: :unsupported_format} | errors]}

        true ->
          {refs, errors}
      end
    end)
  end

  defp policy(metadata) do
    case metadata["material_origins"] do
      origins when is_list(origins) and length(origins) in 1..16 ->
        parsed = Enum.map(origins, &origin/1)

        if Enum.any?(parsed, &is_nil/1),
          do: {:error, :invalid_material_policy},
          else: {:ok, fn url -> origin(url, false) in parsed end}

      _ ->
        {:error, :material_policy_required}
    end
  end

  defp origin(url, configuration? \\ true)

  defp origin(url, configuration?) when is_binary(url) do
    case URI.new(url) do
      {:ok, %{scheme: scheme, host: host, port: port, userinfo: nil} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if not configuration? or
             (uri.path in [nil, "", "/"] and is_nil(uri.query) and is_nil(uri.fragment)),
           do: {scheme, String.downcase(host), port},
           else: nil

      _ ->
        nil
    end
  end

  defp origin(_, _), do: nil

  defp storage_client(options) do
    case Keyword.fetch(options, :rustfs) do
      {:ok, %RustFS{} = client} -> {:ok, client}
      {:ok, _} -> {:error, :invalid_configuration}
      :error -> RustFS.new()
    end
  end

  defp strip_fragment(url), do: URI.to_string(%{URI.parse(url) | fragment: nil})
  defp json_map(map), do: map |> Jason.encode!() |> Jason.decode!()
  defp digest(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  defp failure(stage, reason), do: error(%{materials: [], errors: []}, stage, reason)

  defp error(state, stage, reason) do
    ErrorReporter.report(stage, reason)
    %{state | errors: [%{stage: stage, reason: reason} | state.errors]}
  end
end
