defmodule Lens.Ingestion.SchedulerTest do
  use Lens.DataCase, async: false

  alias Lens.Ingestion.Scheduler
  alias Lens.Content

  test "poll keeps its state when no source is due" do
    state = %{concurrency: 2, running: 0, tick_ms: 60_000}

    assert {:noreply, ^state} = Scheduler.handle_info(:poll, state)
  end

  test "a finished task frees a scheduler slot" do
    state = %{concurrency: 2, running: 1, tick_ms: 1_000}
    expected_state = %{state | running: 0}

    assert {:noreply, ^expected_state} = Scheduler.handle_info({:finished, "source-id"}, state)
  end

  test "a finished task never makes the running count negative" do
    state = %{concurrency: 2, running: 0, tick_ms: 1_000}

    assert {:noreply, ^state} = Scheduler.handle_info({:finished, "source-id"}, state)
  end

  test "releases a failed source task so it cannot consume a scheduler slot" do
    assert {:ok, source} =
             Content.create_source(%{
               source_type: "rss",
               endpoint_url: "http://127.0.0.1:1/unavailable.xml",
               poll_interval_seconds: 60,
               next_fetch_at: DateTime.add(DateTime.utc_now(), -1, :second)
             })

    state = %{concurrency: 1, running: 0, tick_ms: 60_000}
    expected_state = %{state | running: 1}

    assert {:noreply, ^expected_state} = Scheduler.handle_info(:poll, state)

    assert eventually(fn ->
             source = Content.get_source!(source.id)
             source.failure_count == 1 and source_run_count(source.id) == 0
           end)
  end

  defp source_run_count(source_id) do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*) FROM source_runs WHERE source_id = $1", [
        Ecto.UUID.dump!(source_id)
      ])

    count
  end

  defp eventually(predicate, attempts \\ 50)

  defp eventually(predicate, attempts) when attempts > 0 do
    if predicate.() do
      true
    else
      Process.sleep(10)
      eventually(predicate, attempts - 1)
    end
  end

  defp eventually(_predicate, 0), do: false
end
