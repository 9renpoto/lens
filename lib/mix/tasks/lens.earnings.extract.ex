defmodule Mix.Tasks.Lens.Earnings.Extract do
  use Mix.Task
  alias Lens.Earnings.ReleaseCLI

  @shortdoc "Extracts retained PDF originals without starting collection"
  @impl Mix.Task
  def run(args) do
    case ReleaseCLI.validate(args) do
      {:ok, command} ->
        Mix.Task.run("app.config")

        case ReleaseCLI.execute(command) do
          {:ok, json} -> Mix.shell().info(json)
          {:error, reason} -> Mix.raise(to_string(reason))
        end

      {:error, reason} ->
        Mix.raise(to_string(reason))
    end
  end
end
