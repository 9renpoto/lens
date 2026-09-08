defmodule Lens.Ingestion.Scheduler do
  use GenServer
  import Ecto.Query

  alias Lens.Content
  alias Lens.Repo

  @default_concurrency 2
  @default_tick_ms 1_000

  @typedoc "Scheduler state kept only for currently running source tasks."
  @type state :: %{concurrency: pos_integer(), running: non_neg_integer(), tick_ms: pos_integer()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(options) do
    state = %{
      concurrency: Keyword.get(options, :concurrency, @default_concurrency),
      running: 0,
      tick_ms: Keyword.get(options, :tick_ms, @default_tick_ms)
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    slots = max(state.concurrency - state.running, 0)

    claimed = Content.claim_due_sources(DateTime.utc_now(), slots)

    Enum.each(claimed, fn source_id ->
      Task.Supervisor.start_child(Lens.Ingestion.TaskSupervisor, fn -> run(source_id) end)
    end)

    Process.send_after(self(), :poll, state.tick_ms)
    {:noreply, %{state | running: state.running + length(claimed)}}
  end

  def handle_info({:finished, _source_id}, state),
    do: {:noreply, %{state | running: max(state.running - 1, 0)}}

  defp run(source_id) do
    result = Lens.Ingestion.ingest(source_id)
    Content.schedule_next_fetch(source_id, result, DateTime.utc_now())
  after
    Repo.delete_all(from(run in "source_runs", where: run.source_id == ^source_id))
    send(__MODULE__, {:finished, source_id})
  end
end
