defmodule Mix.Tasks.Lens.Search.Rebuild do
  use Mix.Task

  @shortdoc "Rebuilds derived PostgreSQL search data"

  @moduledoc """
  Rebuilds PostgreSQL full-text search data from canonical documents.

      mix lens.search.rebuild [--batch-size 1000]
  """

  @impl Mix.Task
  def run(args) do
    {options, remaining, invalid} = OptionParser.parse(args, strict: [batch_size: :integer])

    if remaining != [] or invalid != [] do
      Mix.raise("usage: mix lens.search.rebuild [--batch-size POSITIVE_INTEGER]")
    end

    Mix.Task.run("app.start")

    case Lens.Search.rebuild(options) do
      :ok -> Mix.shell().info("Search data rebuilt.")
      {:error, :invalid_batch_size} -> Mix.raise("batch size must be a positive integer")
    end
  end
end
