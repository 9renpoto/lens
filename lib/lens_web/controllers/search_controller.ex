defmodule LensWeb.SearchController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.{Content, Search}

  alias LensWeb.ApiSchemas.{
    DocumentProvenanceResponse,
    DocumentResponse,
    ErrorResponse,
    SearchResponse
  }

  alias OpenApiSpex.Schema

  tags(["Search"])

  operation :index,
    summary: "Search canonical documents",
    parameters: [
      q: [in: :query, required: true, schema: %Schema{type: :string, maxLength: 500}],
      limit: [in: :query, schema: %Schema{type: :integer, minimum: 1, maximum: 100}],
      offset: [in: :query, schema: %Schema{type: :integer, minimum: 0}]
    ],
    responses: [
      ok: {"Search results", "application/json", SearchResponse},
      unprocessable_entity: {"Invalid search parameters", "application/json", ErrorResponse}
    ]

  operation :show_document,
    summary: "Get canonical document content",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Canonical document", "application/json", DocumentResponse},
      not_found: {"Document not found", "application/json", ErrorResponse}
    ]

  operation :show_provenance,
    summary: "Get paginated document observation provenance",
    parameters: [
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}],
      limit: [in: :query, schema: %Schema{type: :integer, minimum: 1, maximum: 100}],
      offset: [in: :query, schema: %Schema{type: :integer, minimum: 0, maximum: 2_147_483_647}]
    ],
    responses: [
      ok: {"Document observation provenance", "application/json", DocumentProvenanceResponse},
      not_found: {"Document not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid pagination parameters", "application/json", ErrorResponse}
    ]

  def index(conn, %{"q" => query} = params) do
    with {:ok, options} <- pagination(params), {:ok, results} <- Search.search(query, options) do
      json(conn, %{results: results})
    else
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def index(conn, _),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "q is required"})

  def show_document(conn, %{"id" => id}) do
    case Content.fetch_document(id) do
      {:ok, document} ->
        sources = Content.document_sources(document)

        json(conn, %{
          document:
            Map.take(document, [
              :id,
              :title,
              :canonical_url,
              :content,
              :author,
              :published_at,
              :metadata
            ])
            |> Map.put(:sources, sources)
            |> Map.put(:provenance_url, "/api/documents/#{document.id}/provenance")
        })

      :error ->
        not_found(conn)
    end
  end

  def show_provenance(conn, %{"id" => id} = params) do
    with {:ok, document} <- Content.fetch_document(id),
         {:ok, options} <- pagination(params),
         {:ok, observations} <- Content.list_document_observations(document, options) do
      json(conn, %{
        observations: Enum.map(observations, &render_observation_provenance/1)
      })
    else
      :error ->
        not_found(conn)

      {:error, :invalid_pagination} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_pagination"})
    end
  end

  @sensitive_exact_keys ~w(
    auth authorization token access_token id_token refresh_token
    password pass secret api_key apikey key cookie credential bearer sig signature
  )

  @sensitive_suffixes ~w(_key -key _secret -secret _token -token _auth -auth)

  defp render_observation_provenance(obs) do
    %{
      id: obs.id,
      source_id: obs.source_id,
      observed_at: obs.observed_at,
      content_hash: obs.content_hash,
      entry_url: sanitize_url(obs.entry_url),
      primary_source_url: sanitize_url(obs.primary_source_url),
      feed_format: obs.feed_format || "unknown",
      acquisition_kind: obs.acquisition_kind || "unknown",
      publisher_authority: obs.publisher_authority || "unknown",
      acquisition_metadata_snapshot: sanitize_metadata(obs.acquisition_metadata_snapshot || %{}),
      reported_published_at: obs.reported_published_at
    }
  end

  defp sanitize_url(nil), do: nil

  defp sanitize_url(url) when is_binary(url) do
    uri = URI.parse(url)

    path = if is_binary(uri.path), do: sanitize_path(uri.path), else: nil
    query = if is_binary(uri.query), do: sanitize_query_string(uri.query), else: nil
    fragment = if is_binary(uri.fragment), do: sanitize_fragment(uri.fragment), else: nil

    URI.to_string(%{uri | userinfo: nil, path: path, query: query, fragment: fragment})
  rescue
    _ -> url
  end

  defp sanitize_path(path) when is_binary(path) do
    path
    |> String.split("/")
    |> sanitize_path_segments(false)
    |> Enum.join("/")
  end

  defp sanitize_path_segments([], _redact_next), do: []

  defp sanitize_path_segments([segment | rest], redact_next) do
    if redact_next and segment != "" do
      ["%5BREDACTED%5D" | sanitize_path_segments(rest, false)]
    else
      should_redact_following = sensitive_key?(segment)
      [segment | sanitize_path_segments(rest, should_redact_following)]
    end
  end

  defp sanitize_query_string(query) when is_binary(query) do
    query
    |> String.split("&")
    |> Enum.map(&sanitize_query_param/1)
    |> Enum.join("&")
  end

  defp sanitize_query_param(param) when is_binary(param) do
    case String.split(param, "=", parts: 2) do
      [key_encoded, _val_encoded] ->
        key = URI.decode_www_form(key_encoded)

        if sensitive_key?(key) do
          key_encoded <> "=%5BREDACTED%5D"
        else
          param
        end

      [param_encoded] ->
        key = URI.decode_www_form(param_encoded)

        if sensitive_key?(key) do
          param_encoded <> "=%5BREDACTED%5D"
        else
          param
        end
    end
  end

  defp sanitize_fragment(fragment) when is_binary(fragment) do
    if String.contains?(fragment, "=") do
      sanitize_query_string(fragment)
    else
      fragment
    end
  end

  defp sanitize_metadata(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      key_str = to_string(key)

      if sensitive_key?(key_str) do
        {key, "[REDACTED]"}
      else
        {key, sanitize_metadata(value)}
      end
    end)
  end

  defp sanitize_metadata(list) when is_list(list) do
    Enum.map(list, &sanitize_metadata/1)
  end

  defp sanitize_metadata(value), do: value

  defp sensitive_key?(key) when is_binary(key) do
    downcase_key = String.downcase(key)

    downcase_key in @sensitive_exact_keys or
      Enum.any?(@sensitive_suffixes, &String.ends_with?(downcase_key, &1))
  end

  defp pagination(params) do
    limit_param = Map.get(params, "limit", "20")
    offset_param = Map.get(params, "offset", "0")

    with true <- is_binary(limit_param) and is_binary(offset_param),
         {limit, ""} <- Integer.parse(limit_param),
         {offset, ""} <- Integer.parse(offset_param) do
      {:ok, [limit: limit, offset: offset]}
    else
      _ -> {:error, :invalid_pagination}
    end
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})
end
