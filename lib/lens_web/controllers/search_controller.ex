defmodule LensWeb.SearchController do
  use LensWeb, :controller
  alias Lens.{Content, Search}

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
    document = Content.get_document!(id)

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
    })
  end

  defp pagination(params) do
    with {limit, ""} <- Integer.parse(Map.get(params, "limit", "20")),
         {offset, ""} <- Integer.parse(Map.get(params, "offset", "0")) do
      {:ok, [limit: limit, offset: offset]}
    else
      _ -> {:error, :invalid_pagination}
    end
  end
end
