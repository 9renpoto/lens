defmodule Mix.Tasks.Lens.Db.Prepare do
  @shortdoc "Initialize or migrate a supported database"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    Lens.Release.prepare()
  end
end
