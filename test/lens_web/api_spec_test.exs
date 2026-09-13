defmodule LensWeb.ApiSpecTest do
  use ExUnit.Case, async: true

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
  end
end
