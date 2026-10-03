defmodule Mix.Tasks.Lens.Earnings.ExtractTest do
  use Lens.DataCase
  import ExUnit.CaptureIO

  alias Mix.Tasks.Lens.Earnings.Extract
  alias Lens.Earnings.ReleaseCLI

  @tag skip: not match?({:unix, :linux}, :os.type())
  test "CLI extracts, retries and bounds regeneration using retained originals" do
    assert_raise Mix.Error, ~r/without app.start/, fn ->
      Extract.run(["--original", Ecto.UUID.generate()])
    end

    :ok = Supervisor.terminate_child(Lens.Supervisor, Lens.Ingestion.Scheduler)

    on_exit(fn ->
      {:ok, _pid} = Supervisor.restart_child(Lens.Supervisor, Lens.Ingestion.Scheduler)
      :ok = :sys.suspend(Lens.Ingestion.Scheduler)
    end)

    retained =
      for kind <- ["text", "image"] do
        bytes = File.read!("test/fixtures/earnings-#{kind}.pdf")

        {:ok, result} =
          Lens.Earnings.record_success(%{
            bytes: bytes,
            acquisition_id: "cli-#{kind}",
            issuer_code: "6857",
            acquired_at: ~U[2026-09-27 01:00:00.000000Z],
            url: "https://publisher.invalid/#{kind}.pdf"
          })

        {result.original, bytes}
      end

    [{text, _}, {image, _}] = retained
    run = fn args -> capture_io(fn -> Extract.run(args) end) |> Jason.decode!() end

    release_output =
      capture_io(fn -> assert :ok = ReleaseCLI.main(["--", "--original", text.id]) end)

    assert Jason.decode!(release_output)["status"] == "succeeded"
    assert run.(["--original", text.id])["status"] == "succeeded"
    assert run.(["--original", image.id])["failure_reason"] == "empty_output"
    assert run.(["--retry", image.id])["status"] == "failed"
    response = run.(["--regenerate", "--limit", "1"])
    assert length(response["results"]) == 1
    assert response["next_after"] in [text.id, image.id]
    assert Repo.aggregate(Lens.Earnings.Extraction, :count) == 5
    assert Repo.aggregate(Lens.Earnings.Acquisition, :count) == 2

    for {original, bytes} <- retained do
      assert Lens.Earnings.original_bytes(original.id) == {:ok, bytes}
    end

    assert Process.whereis(Lens.Ingestion.Scheduler) == nil

    assert_raise Mix.Error, ~r/not_found/, fn ->
      Extract.run(["--original", Ecto.UUID.generate()])
    end
  end

  test "rejects unbounded regeneration and ambiguous commands before starting services" do
    for args <- [
          [],
          ["--regenerate"],
          ["--regenerate", "--limit", "0"],
          ["--regenerate", "--limit", "101"],
          ["--retry", "invalid"],
          ["--original", Ecto.UUID.generate(), "--regenerate", "--limit", "1"],
          ["--unknown"]
        ] do
      assert_raise Mix.Error, fn -> Extract.run(args) end
    end
  end
end
