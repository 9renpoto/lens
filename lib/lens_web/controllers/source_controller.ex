defmodule LensWeb.SourceController do
  use LensWeb, :controller

  alias Lens.Content

  def index(conn, _params),
    do: json(conn, %{sources: Enum.map(Content.list_sources(), &source_json/1)})

  def show(conn, %{"id" => id}), do: json(conn, %{source: source_json(Content.get_source!(id))})

  def create(conn, %{"source" => attrs}) do
    case Content.create_source(attrs) do
      {:ok, source} -> conn |> put_status(:created) |> json(%{source: source_json(source)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id, "source" => attrs}) do
    case Content.update_source(Content.get_source!(id), attrs) do
      {:ok, source} -> json(conn, %{source: source_json(source)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  defp validation_error(conn, changeset) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors(changeset)})
  end

  defp source_json(source) do
    Map.take(source, [
      :id,
      :source_type,
      :feed_format,
      :acquisition_kind,
      :publisher_authority,
      :original_feed_url,
      :acquisition_metadata,
      :endpoint_url,
      :title,
      :enabled,
      :poll_interval_seconds,
      :next_fetch_at,
      :last_attempt_at,
      :last_success_at,
      :last_error,
      :failure_count
    ])
  end

  defp errors(changeset),
    do: Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
end
