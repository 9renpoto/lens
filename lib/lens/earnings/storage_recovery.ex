defmodule Lens.Earnings.StorageRecovery do
  @moduledoc "Optional supervised polling of durable storage work; no in-memory work queue."
  use GenServer
  alias Lens.Earnings.{RustFS, StorageWork}

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(options) do
    state = %{
      enabled: Keyword.get(options, :enabled, false),
      client: Keyword.get(options, :client)
    }

    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:poll, _from, state), do: {:reply, poll(state), state}

  @impl true
  def handle_info(:poll, state) do
    poll(state)
    schedule(state)
    {:noreply, state}
  end

  defp poll(%{client: %RustFS{} = client}), do: StorageWork.recover_due(client, 1)

  defp poll(_) do
    case RustFS.new() do
      {:ok, client} -> StorageWork.recover_due(client, 1)
      {:error, reason} -> StorageWork.recover_due({:error, reason}, 1)
    end
  end

  defp schedule(%{enabled: true}), do: Process.send_after(self(), :poll, 1000)
  defp schedule(_), do: :ok
end
