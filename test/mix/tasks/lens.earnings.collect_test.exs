defmodule Mix.Tasks.Lens.Earnings.CollectTest do
  use Lens.DataCase

  alias Lens.Earnings.HTTPCheck

  @task "lens.earnings.collect"
  @pdf_url "https://publisher.invalid/selected.pdf?edition=2"

  test "validates both positional arguments before starting collection" do
    id = Ecto.UUID.generate()

    for args <- [[], [id], [id, @pdf_url, "extra"]] do
      assert_raise Mix.Error, ~r/usage: mix lens\.earnings\.collect SOURCE_ID PDF_URL/, fn ->
        Mix.Task.rerun(@task, args)
      end
    end

    for source_id <- ["invalid", String.duplicate("x", 16)] do
      assert_raise Mix.Error, ~r/invalid source ID/, fn ->
        Mix.Task.rerun(@task, [source_id, @pdf_url])
      end
    end

    for url <- ["/selected.pdf", "https://user:secret@publisher.invalid/selected.pdf"] do
      assert_raise Mix.Error, ~r/invalid PDF URL/, fn ->
        Mix.Task.rerun(@task, [id, url])
      end
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
  end

  test "a valid invocation reports an unknown source without starting scheduled ingestion" do
    :ok = Supervisor.terminate_child(Lens.Supervisor, Lens.Ingestion.Scheduler)

    on_exit(fn ->
      {:ok, _pid} = Supervisor.restart_child(Lens.Supervisor, Lens.Ingestion.Scheduler)
      :ok = :sys.suspend(Lens.Ingestion.Scheduler)
    end)

    assert_raise Mix.Error, "enabled_source_not_found", fn ->
      Mix.Task.rerun(@task, [Ecto.UUID.generate(), @pdf_url])
    end

    assert Process.whereis(Lens.Ingestion.Scheduler) == nil
    assert Repo.aggregate(HTTPCheck, :count) == 0
  end
end
