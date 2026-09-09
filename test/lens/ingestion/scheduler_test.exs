defmodule Lens.Ingestion.SchedulerTest do
  use Lens.DataCase, async: false

  alias Lens.Ingestion.Scheduler

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
end
