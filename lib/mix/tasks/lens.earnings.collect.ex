defmodule Mix.Tasks.Lens.Earnings.Collect do
  use Mix.Task
  alias Lens.Earnings.{Collector, HTTPCheck}

  @shortdoc "Collects one PDF from an enabled registered earnings source"
  @usage "usage: mix lens.earnings.collect SOURCE_ID PDF_URL"

  @impl Mix.Task
  def run([source_id, pdf_url]) do
    with {:ok, _} <- Ecto.UUID.dump(source_id),
         true <- HTTPCheck.valid_url?(pdf_url) do
      Mix.Task.run("app.config")
      start_dependencies()

      case Collector.run_selected(source_id, pdf_url, max_operations: 2) do
        {:ok, result} -> report(result)
        {:error, reason} -> Mix.raise(to_string(reason))
      end
    else
      :error -> Mix.raise("invalid source ID (expected a UUID)")
      false -> Mix.raise("invalid PDF URL (expected an absolute HTTP(S) URL without credentials)")
    end
  end

  def run(_), do: Mix.raise(@usage)

  defp start_dependencies do
    if Process.whereis(Lens.Ingestion.Scheduler) do
      Mix.raise("run collection in a fresh process without app.start")
    end

    for app <- [:ecto_sql, :postgrex, :req] do
      {:ok, _} = Application.ensure_all_started(app)
    end

    unless Process.whereis(Lens.Repo) do
      {:ok, _} = Lens.Repo.start_link()
    end
  end

  defp report(result) do
    checks =
      Enum.map(
        result.checks,
        &Map.take(&1, [:id, :kind, :status, :failure_reason, :acquisition_id])
      )

    Mix.shell().info(Jason.encode!(%{checks: checks, stopped: result.stopped}))
    if result.stopped, do: Mix.raise(to_string(result.stopped))
  end
end
