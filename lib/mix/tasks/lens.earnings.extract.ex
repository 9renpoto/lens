defmodule Mix.Tasks.Lens.Earnings.Extract do
  use Mix.Task
  alias Lens.Earnings.Processing

  @shortdoc "Extracts retained PDF originals without starting collection"
  @usage "usage: mix lens.earnings.extract (--original UUID | --retry UUID | --regenerate --limit 1..100) [--after-original UUID] [--timeout-ms 1..30000] [--max-output-bytes 1..8388608]"

  @impl Mix.Task
  def run(args) do
    {options, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          original: :string,
          retry: :string,
          regenerate: :boolean,
          limit: :integer,
          after_original: :string,
          timeout_ms: :integer,
          max_output_bytes: :integer
        ]
      )

    command = validate!(options, rest, invalid)
    start_repo!()

    case command do
      {:original, id} ->
        report_single(Processing.extract(id, options))

      {:retry, id} ->
        report_single(Processing.retry_failed(id, options))

      :regenerate ->
        case Processing.regenerate(options) do
          {:ok, batch} ->
            results = Enum.map(batch.results, fn {_id, result} -> summary(result) end)
            Mix.shell().info(Jason.encode!(%{results: results, next_after: batch.next_after}))

          {:error, reason} ->
            Mix.raise(to_string(reason))
        end
    end
  end

  defp validate!(options, rest, invalid) do
    commands = Keyword.take(options, [:original, :retry, :regenerate])
    unique = length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options)))
    timeout = Keyword.get(options, :timeout_ms, 20_000)
    output = Keyword.get(options, :max_output_bytes, 8_388_608)

    valid =
      rest == [] and invalid == [] and unique and length(commands) == 1 and
        timeout in 1..30_000 and output in 1..8_388_608

    case commands do
      [regenerate: true] ->
        limit = Keyword.get(options, :limit)
        cursor = Keyword.get(options, :after_original)

        if valid and is_integer(limit) and limit in 1..100 and
             (is_nil(cursor) or match?({:ok, _}, Ecto.UUID.cast(cursor))),
           do: :regenerate,
           else: Mix.raise(@usage)

      [{command, id}] when command in [:original, :retry] ->
        if valid and match?({:ok, _}, Ecto.UUID.cast(id)) and
             not Keyword.has_key?(options, :limit) and
             not Keyword.has_key?(options, :after_original),
           do: {command, id},
           else: Mix.raise(@usage)

      _ ->
        Mix.raise(@usage)
    end
  end

  defp start_repo! do
    if Process.whereis(Lens.Ingestion.Scheduler) do
      Mix.raise("run extraction in a fresh Mix process without app.start")
    end

    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    unless Process.whereis(Lens.Repo), do: Lens.Repo.start_link() |> require_repo!()
  end

  defp require_repo!({:ok, _pid}), do: :ok

  defp require_repo!({:error, reason}),
    do: Mix.raise("cannot start repository: #{inspect(reason)}")

  defp report_single({:error, reason}), do: Mix.raise(to_string(reason))
  defp report_single(result), do: Mix.shell().info(Jason.encode!(summary(result)))

  defp summary({:ok, attempt}) do
    Map.take(attempt, [:id, :original_id, :status, :failure_reason, :extractor_version])
  end

  defp summary({:error, reason}), do: %{error: to_string(reason)}
end
