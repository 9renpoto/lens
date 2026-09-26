defmodule LensWeb.EarningsControllerTest do
  use Lens.DataCase
  import Phoenix.ConnTest
  import OpenApiSpex.TestAssertions
  alias Lens.Earnings
  alias Lens.Earnings.Extractions
  @endpoint LensWeb.Endpoint

  test "a release remains inspectable while pending and failed without invented text" do
    {:ok, retained} =
      Earnings.record_success(%{
        bytes: "%PDF-api",
        acquisition_id: "api",
        issuer_code: "6857",
        acquired_at: ~U[2026-09-27 01:00:00.000000Z],
        url: "https://example.test/api.pdf",
        release: %{fiscal_year_end: ~D[2027-03-31], period: "q1", category: "earnings_release"}
      })

    path = "/api/earnings/releases/#{retained.release.id}"
    {:ok, attempt} = Extractions.begin(retained.original.id, "fixture", "1")
    pending = build_conn() |> get(path) |> json_response(200)
    assert pending["extraction"] == nil
    assert pending["latest_attempt"]["status"] == "pending"
    assert_response_schema(pending, "EarningsReleaseResponse", LensWeb.ApiSpec.spec())
    {:ok, _} = Extractions.fail(attempt.id, "empty_output")
    failed = build_conn() |> get(path) |> json_response(200)
    assert failed["extraction"] == nil
    assert failed["latest_attempt"]["failure_reason"] == "empty_output"
    {:ok, success} = Extractions.begin(retained.original.id, "fixture", "2")
    {:ok, _} = Extractions.succeed(success.id, "売上高\n\n営業利益")
    response = build_conn() |> get(path) |> json_response(200)
    assert response["extraction"]["text"] == "売上高\n\n営業利益"
    assert response["extraction"]["original_id"] == retained.original.id
    assert response["extraction"]["extractor_version"] == "2"
    refute response["stale"]
    assert_response_schema(response, "EarningsReleaseResponse", LensWeb.ApiSpec.spec())
    search = build_conn() |> get("/api/search", %{q: "営業利益"}) |> json_response(200)
    assert hd(search["results"])["provenance_url"] == path
    assert_response_schema(search, "SearchResponse", LensWeb.ApiSpec.spec())
  end

  test "unknown or invalid release identifiers return not found" do
    for id <- ["invalid", Ecto.UUID.generate()] do
      assert build_conn() |> get("/api/earnings/releases/#{id}") |> json_response(404) ==
               %{"error" => "not_found"}
    end
  end
end
