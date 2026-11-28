defmodule Mix.Tasks.Lens.Earnings.Brief do
  use Mix.Task

  alias Lens.Earnings.Brief
  alias Lens.Earnings.Brief.Hypothesis

  @shortdoc "Renders a local earnings brief from one cited disclosure record"
  @usage "Usage: mix lens.earnings.brief [--facts-only] INPUT.json"

  @impl Mix.Task
  def run(args) when is_list(args) do
    case parse_args(args) do
      {:ok, path, facts_only?} ->
        case Brief.load_file(path) do
          {:ok, brief} ->
            output_brief(brief, facts_only?)

          {:error, reason} ->
            Mix.raise(Brief.format_error(reason))
        end

      :error ->
        Mix.raise(@usage)
    end
  end

  defp parse_args(args) do
    case OptionParser.parse(args, strict: [facts_only: :boolean]) do
      {opts, [path], []} when is_binary(path) and byte_size(path) > 0 ->
        {:ok, path, Keyword.get(opts, :facts_only, false)}

      _ ->
        :error
    end
  end

  defp output_brief(brief, true) do
    Mix.shell().info(Brief.render_facts(brief))
  end

  defp output_brief(brief, false) do
    {:ok, _} = Application.ensure_all_started(:req)

    result =
      with {:ok, client} <- Hypothesis.client_from_env() do
        Hypothesis.generate(brief, client)
      end

    Mix.shell().info(Brief.render(brief, result))

    case result do
      {:ok, _hypothesis} -> :ok
      {:error, reason} -> Mix.raise(Hypothesis.format_error(reason))
    end
  end
end
