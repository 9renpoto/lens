defmodule Mix.Tasks.Lens.Ingest do
  use Mix.Task

  @shortdoc "Ingests one configured feed source"

  @moduledoc """
  Ingests a configured source by ID.

      mix lens.ingest SOURCE_ID
  """

  @impl Mix.Task
  def run([source_id]) do
    Mix.Task.run("app.start")
    result = Lens.Ingestion.ingest(source_id)
    Mix.shell().info(inspect(result, pretty: true))
  end

  def run(_args), do: Mix.raise("usage: mix lens.ingest SOURCE_ID")
end
