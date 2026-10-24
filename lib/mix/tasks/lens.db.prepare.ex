defmodule Mix.Tasks.Lens.Db.Prepare do
  @shortdoc "Initialize an empty database or verify the current schema"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    Lens.Release.prepare()
  end
end
