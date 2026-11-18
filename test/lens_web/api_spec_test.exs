defmodule LensWeb.ApiSpecTest do
  use ExUnit.Case, async: true

  test "listing-source operations are absent from the router and OpenAPI" do
    document = LensWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()

    refute Enum.any?(Map.keys(document["paths"]), &String.contains?(&1, "/earnings-sources"))

    refute Enum.any?(
             Map.keys(document["components"]["schemas"]),
             &String.contains?(&1, "EarningsSource")
           )

    base = "/api/targets/#{Ecto.UUID.generate()}/earnings-sources"

    for {method, path} <- [
          {"GET", base},
          {"POST", base},
          {"GET", base <> "/id"},
          {"PATCH", base <> "/id"}
        ] do
      assert Phoenix.Router.route_info(LensWeb.Router, method, path, "localhost") == :error
    end
  end

  test "historical membership is absent from target routes and OpenAPI" do
    document = LensWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()
    paths = document["paths"]
    schemas = document["components"]["schemas"]

    refute Map.has_key?(paths, "/api/targets/{target_id}/memberships")
    refute Map.has_key?(paths, "/api/targets/{target_id}/memberships/{id}")
    refute Enum.any?(Map.keys(schemas), &String.contains?(&1, "Membership"))
    refute Map.has_key?(schemas["Target"]["properties"], "memberships")

    parameters = paths["/api/targets"]["get"]["parameters"] || []
    refute Enum.any?(parameters, &(&1["name"] == "as_of"))

    base = "/api/targets/#{Ecto.UUID.generate()}/memberships"

    for {method, path} <- [{"GET", base}, {"POST", base}, {"PATCH", base <> "/id"}] do
      assert Phoenix.Router.route_info(LensWeb.Router, method, path, "localhost") == :error
    end
  end

  test "original retrieval remains documented without retired work operations or schemas" do
    document = LensWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()
    paths = document["paths"]
    refute Map.has_key?(paths, "/api/earnings/storage-work")
    refute Map.has_key?(paths, "/api/earnings/storage-work/{id}")

    refute Enum.any?(
             Map.keys(document["components"]["schemas"]),
             &String.contains?(&1, "StorageWork")
           )

    original = paths["/api/earnings/originals/{id}"]["get"]

    assert original["responses"]["200"]["content"]["application/pdf"]["schema"]["format"] ==
             "binary"

    assert original["responses"]["503"]["content"]["application/json"]
  end

  test "describes every public JSON API operation" do
    document =
      LensWeb.ApiSpec.spec()
      |> Jason.encode!()
      |> Jason.decode!()

    assert document["openapi"] == "3.0.3"

    assert document["paths"]["/api/health"]["get"]["operationId"] ==
             "LensWeb.HealthController.show"

    assert document["paths"]["/api/ready"]["get"]["operationId"] ==
             "LensWeb.HealthController.ready"

    assert document["paths"]["/api/sources"]["get"]["operationId"] ==
             "LensWeb.SourceController.index"

    assert document["paths"]["/api/sources"]["post"]["operationId"] ==
             "LensWeb.SourceController.create"

    assert document["paths"]["/api/sources/{id}"]["get"]["operationId"] ==
             "LensWeb.SourceController.show"

    assert document["paths"]["/api/sources/{id}"]["patch"]["operationId"] ==
             "LensWeb.SourceController.update"

    assert document["paths"]["/api/sources/{id}"]["put"]["operationId"] ==
             "LensWeb.SourceController.replace"

    assert document["paths"]["/api/search"]["get"]["operationId"] ==
             "LensWeb.SearchController.index"

    assert document["paths"]["/api/documents/{id}"]["get"]["operationId"] ==
             "LensWeb.SearchController.show_document"

    assert document["paths"]["/api/documents/{id}/provenance"]["get"]["operationId"] ==
             "LensWeb.SearchController.show_provenance"
  end
end
