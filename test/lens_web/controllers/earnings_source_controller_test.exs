defmodule LensWeb.EarningsSourceControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest
  import OpenApiSpex.TestAssertions

  alias Lens.Analysis
  alias LensWeb.ApiSpec

  @endpoint LensWeb.Endpoint

  setup do
    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Synthetic target",
        sector: "Test",
        active: false
      })

    {:ok, other} =
      Analysis.create_target(%{
        security_code: "6758",
        market: "TSE",
        display_name: "Other target",
        sector: "Test"
      })

    %{target: target, other: other, path: "/api/targets/#{target.id}/earnings-sources"}
  end

  test "registers multiple sources without membership or PDF settings and keeps target state", %{
    target: target,
    path: path
  } do
    first = create(path, %{listing_url: "https://publisher.invalid/results"})
    assert first["enabled"] == true
    assert first["target_id"] == target.id
    assert_response_schema(%{"source" => first}, "EarningsSourceResponse", ApiSpec.spec())
    second = create(path, %{listing_url: "https://publisher.invalid/corrections", enabled: false})
    assert second["enabled"] == false

    response = build_conn() |> get(path) |> json_response(200)

    assert Enum.map(response["sources"], & &1["id"]) |> Enum.sort() ==
             Enum.sort([first["id"], second["id"]])

    assert_response_schema(response, "EarningsSourcesResponse", ApiSpec.spec())

    assert build_conn() |> get("#{path}/#{first["id"]}") |> json_response(200) == %{
             "source" => first
           }

    assert {:ok, %{active: false, memberships: []}} = Analysis.fetch_target(target.id)
  end

  test "partial updates preserve omitted fields, allow empty patches and reject null or blank defaults",
       %{path: path} do
    source = create(path, %{listing_url: "https://publisher.invalid/results", enabled: false})
    detail = "#{path}/#{source["id"]}"

    response =
      build_conn()
      |> patch(detail, source: %{listing_url: "https://publisher.invalid/new"})
      |> json_response(200)

    assert response["source"]["enabled"] == false
    assert build_conn() |> patch(detail, source: %{}) |> json_response(200) == response
    response = build_conn() |> patch(detail, source: %{enabled: true}) |> json_response(200)
    assert response["source"]["listing_url"] == "https://publisher.invalid/new"
    assert response["source"]["enabled"] == true

    for attrs <- [%{enabled: nil}, %{enabled: ""}, %{listing_url: nil}, %{listing_url: ""}] do
      assert build_conn() |> patch(detail, source: attrs) |> json_response(422)
    end

    assert build_conn() |> get(detail) |> json_response(200) == response
  end

  test "rejects duplicates on creation and update but allows one URL for different targets", %{
    path: path,
    other: other
  } do
    attrs = %{listing_url: "https://publisher.invalid/results"}
    create(path, attrs)
    errors = build_conn() |> post(path, source: attrs) |> json_response(422)
    assert errors["errors"]["listing_url"]
    create("/api/targets/#{other.id}/earnings-sources", attrs)
    source = create(path, %{listing_url: "https://publisher.invalid/other"})
    errors = build_conn() |> patch("#{path}/#{source["id"]}", source: attrs) |> json_response(422)
    assert errors["errors"]["listing_url"]
  end

  test "scopes details and updates to the target and rejects reassignment", %{
    path: path,
    other: other
  } do
    source = create(path, %{listing_url: "https://publisher.invalid/results"})
    detail = "#{path}/#{source["id"]}"
    wrong = "/api/targets/#{other.id}/earnings-sources/#{source["id"]}"
    assert build_conn() |> get(wrong) |> json_response(404)
    assert build_conn() |> patch(wrong, source: %{enabled: false}) |> json_response(404)
    assert build_conn() |> patch(detail, source: %{target_id: other.id}) |> json_response(422)

    assert build_conn()
           |> post(path,
             source: %{target_id: other.id, listing_url: "https://publisher.invalid/other"}
           )
           |> json_response(422)

    assert build_conn() |> get("#{path}/invalid") |> json_response(404)
    assert build_conn() |> get("/api/targets/invalid/earnings-sources") |> json_response(404)
  end

  test "validates listing URLs and request envelopes without contacting publishers", %{path: path} do
    for url <- [
          "relative",
          "ftp://publisher.invalid/results",
          "https://user:pass@publisher.invalid/results",
          "https://publisher.invalid/file.pdf",
          "https://publisher.invalid/file.PDF?download=1",
          "https://publisher.invalid/" <> String.duplicate("x", 4096)
        ] do
      errors = build_conn() |> post(path, source: %{listing_url: url}) |> json_response(422)
      assert errors["errors"]["listing_url"]
    end

    for attrs <- [
          %{},
          %{enabled: nil, listing_url: "https://publisher.invalid/results"},
          %{enabled: "", listing_url: "https://publisher.invalid/results"}
        ] do
      assert build_conn() |> post(path, source: attrs) |> json_response(422)
    end

    assert build_conn() |> post(path, source: []) |> json_response(422)
    assert build_conn() |> post(path, %{}) |> json_response(422)

    assert build_conn()
           |> post("/api/targets/#{Ecto.UUID.generate()}/earnings-sources",
             source: %{listing_url: "https://publisher.invalid/results"}
           )
           |> json_response(404)
  end

  test "listing URLs have a 2048-byte limit including multibyte characters", %{path: path} do
    prefix = "https://publisher.invalid/"
    url = prefix <> String.duplicate("x", 2048 - byte_size(prefix))
    assert create(path, %{listing_url: url})["listing_url"] == url

    for oversized <- [url <> "x", prefix <> String.duplicate("あ", 680)] do
      response =
        build_conn() |> post(path, source: %{listing_url: oversized}) |> json_response(422)

      assert response["errors"]["listing_url"]
    end
  end

  defp create(path, attrs),
    do: build_conn() |> post(path, source: attrs) |> json_response(201) |> Map.fetch!("source")
end
