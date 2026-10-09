defmodule Lens.Earnings.StorageRollbackCLI do
  @moduledoc "Bounded entry point for explicitly restoring originals to PostgreSQL."

  alias Lens.Earnings.{RustFS, StorageMigration}

  def validate(args) do
    {options, remaining, invalid} =
      OptionParser.parse(args, strict: [limit: :integer, after: :string])

    switches =
      args
      |> Enum.filter(&String.starts_with?(&1, "--"))
      |> Enum.map(&(String.split(&1, "=", parts: 2) |> hd()))

    limit = Keyword.get(options, :limit, 10)
    cursor = Keyword.get(options, :after)

    valid =
      remaining == [] and invalid == [] and length(switches) == length(Enum.uniq(switches)) and
        limit in 1..100 and
        (is_nil(cursor) or match?({:ok, _}, Ecto.UUID.cast(cursor)))

    if valid do
      result = [limit: limit]
      result = if cursor, do: Keyword.put(result, :after, cursor), else: result
      {:ok, result}
    else
      {:error, :invalid_options}
    end
  end

  def run(args, client \\ nil) do
    with {:ok, options} <- validate(args),
         :ok <- start_repo(),
         {:ok, client} <- storage_client(client),
         {:ok, result} <- StorageMigration.rollback_batch(client, options) do
      json = Jason.encode!(result)

      if result.failures == [],
        do: {:ok, json},
        else: {:error, {:rollback_incomplete, json}}
    end
  end

  defp storage_client(%RustFS{} = client), do: {:ok, client}
  defp storage_client(nil), do: RustFS.new()
  defp storage_client(_), do: {:error, :invalid_configuration}

  defp start_repo do
    with {:ok, _} <- Application.ensure_all_started(:ecto_sql),
         {:ok, _} <- Application.ensure_all_started(:postgrex),
         :ok <- start_repo_if_needed() do
      :ok
    else
      {:error, reason} -> {:error, {:repository_unavailable, reason}}
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
end
