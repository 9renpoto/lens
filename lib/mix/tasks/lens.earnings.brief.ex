defmodule Mix.Tasks.Lens.Earnings.Brief do
  use Mix.Task

  alias Lens.Earnings.Brief

  @shortdoc "Renders a local earnings brief from one cited disclosure record"

  @impl Mix.Task
  def run([path]) when is_binary(path) and byte_size(path) > 0 do
    case Brief.load_file(path) do
      {:ok, brief} ->
        Mix.shell().info(Brief.render_facts(brief))

      {:error, reason} ->
        Mix.raise(Brief.format_error(reason))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix lens.earnings.brief INPUT.json")
  end
end
