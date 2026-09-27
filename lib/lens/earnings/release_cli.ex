defmodule Lens.Earnings.ReleaseCLI do
  @moduledoc "Bounded extraction entry point for Mix tasks and production releases."

  alias Lens.Earnings.{Extraction, Processing}

  @usage "usage: lens-earnings-extract (--original UUID | --retry UUID | --regenerate --limit 1..100) [--after-original UUID] [--timeout-ms 1..30000] [--max-output-bytes 1..8388608]"

  def validate(args) do
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

    commands = Keyword.take(options, [:original, :retry, :regenerate])

    switches =
      args
      |> Enum.filter(&String.starts_with?(&1, "--"))
      |> Enum.map(&(String.split(&1, "=", parts: 2) |> hd()))

    unique = length(switches) == length(Enum.uniq(switches))
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
           do: {:ok, {:regenerate, options}},
           else: {:error, :invalid_options}

      [{command, id}] when command in [:original, :retry] ->
        if valid and match?({:ok, _}, Ecto.UUID.cast(id)) and
             not Keyword.has_key?(options, :limit) and
             not Keyword.has_key?(options, :after_original),
           do: {:ok, {command, id, options}},
           else: {:error, :invalid_options}

      _ ->
        {:error, :invalid_options}
    end
  end

  def execute(command) do
    with :ok <- start_repo() do
      command |> process() |> encode_result()
    end
  end

  def main(args, halt \\ &System.halt/1) do
    previous_level = Logger.level()
    Logger.configure(level: :warning)
    result = run(args)
    Logger.configure(level: previous_level)

    case result do
      {:ok, json} ->
        IO.puts(json)
        :ok

      {:error, reason} ->
        IO.puts(:stderr, error_message(reason))
        halt.(1)
    end
  end

  def run(args) do
    args = Enum.drop_while(args, &(&1 == "--"))

    with {:ok, command} <- validate(args),
         {:ok, json} <- execute(command) do
      {:ok, json}
    end
  end

  def usage, do: @usage

  defp start_repo do
    if Process.whereis(Lens.Ingestion.Scheduler) do
      {:error, "run extraction in a fresh process without app.start"}
    else
      with {:ok, _} <- Application.ensure_all_started(:ecto_sql),
           {:ok, _} <- Application.ensure_all_started(:postgrex),
           :ok <- start_repo_if_needed() do
        :ok
      else
        {:error, reason} -> {:error, "cannot start repository: #{inspect(reason)}"}
      end
    end
  end

  defp start_repo_if_needed do
    if Process.whereis(Lens.Repo) do
      :ok
    else
      case Lens.Repo.start_link() do
        {:ok, _pid} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp process({:original, id, options}), do: Processing.extract(id, options)
  defp process({:retry, id, options}), do: Processing.retry_failed(id, options)
  defp process({:regenerate, options}), do: Processing.regenerate(options)

  defp encode_result({:ok, %Extraction{} = attempt}),
    do: {:ok, Jason.encode!(summary(attempt))}

  defp encode_result({:ok, %{results: results, next_after: cursor}}) do
    payload = %{
      results: Enum.map(results, fn {_id, result} -> render_result(result) end),
      next_after: cursor
    }

    {:ok, Jason.encode!(payload)}
  end

  defp encode_result({:error, reason}), do: {:error, reason}

  def render_result({:ok, attempt}), do: summary(attempt)
  def render_result({:error, reason}), do: %{error: to_string(reason)}

  defp summary(attempt) do
    Map.take(attempt, [
      :id,
      :original_id,
      :status,
      :failure_reason,
      :extractor_version,
      :extraction_options
    ])
  end

  def error_message(:invalid_options), do: @usage
  def error_message(reason) when is_atom(reason), do: to_string(reason)
  def error_message(reason) when is_binary(reason), do: reason
end
