defmodule Mix.Tasks.Lens.Earnings.Storage.Rollback do
  use Mix.Task

  alias Lens.Earnings.StorageRollbackCLI

  @shortdoc "Restores RustFS-only originals to verified PostgreSQL storage"

  @moduledoc """
  Explicitly restores a bounded batch of originals to PostgreSQL.

      mix lens.earnings.storage.rollback [--limit 1..100] [--after UUID]
  """

  @impl Mix.Task
  def run(args) do
    case StorageRollbackCLI.run(args) do
      {:ok, json} ->
        Mix.shell().info(json)

      {:error, {:rollback_incomplete, json}} ->
        Mix.shell().info(json)
        Mix.raise("rollback batch had failures; the write fence remains active")

      {:error, :invalid_options} ->
        Mix.raise("usage: mix lens.earnings.storage.rollback [--limit 1..100] [--after UUID]")

      {:error, reason} ->
        Mix.raise("rollback failed: #{inspect(reason)}")
    end
  end
end
