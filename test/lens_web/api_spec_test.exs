defmodule LensWeb.ApiSpecTest do
  use ExUnit.Case, async: true

  test "earnings source creation and updates require a JSON request body" do
    document = LensWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()

    for {path, method} <- [
          {"/api/targets/{target_id}/earnings-sources", "post"},
          {"/api/targets/{target_id}/earnings-sources/{id}", "patch"}
        ] do
      body = document["paths"][path][method]["requestBody"]
      assert body["required"] == true
      assert body["content"]["application/json"]["schema"]
    end
  end

  test "operator storage operations describe bounds, strict work fields and binary originals" do
    document = LensWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()
    paths = document["paths"]
    list = paths["/api/earnings/storage-work"]["get"]
    assert list["responses"]["200"]["content"]["application/json"]
    assert list["responses"]["422"]
    assert Enum.find(list["parameters"], &(&1["name"] == "limit"))["schema"]["maximum"] == 100

    assert Enum.find(list["parameters"], &(&1["name"] == "offset"))["schema"]["maximum"] ==
             2_147_483_647

    assert paths["/api/earnings/storage-work/{id}"]["get"]["responses"]["404"]
    original = paths["/api/earnings/originals/{id}"]["get"]

    assert original["responses"]["200"]["content"]["application/pdf"]["schema"]["format"] ==
             "binary"

    assert original["responses"]["503"]["content"]["application/json"]
    schema = document["components"]["schemas"]["EarningsStorageWork"]
    assert schema["additionalProperties"] == false
    assert Enum.sort(Map.keys(schema["properties"])) == ~w(acquisition_id id status updated_at)
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
