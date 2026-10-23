defmodule LensWeb.InvestigationCandidateControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest
  import OpenApiSpex.TestAssertions

  @endpoint LensWeb.Endpoint
  @path "/api/investigation-candidates"

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        title: "Revenue & margins",
        body: "Investigate the change.",
        published_at: "2026-10-21T09:30:00+09:00"
      },
      overrides
    )
  end

  test "registration persists a server-assigned identity and normalized publication time" do
    response = build_conn() |> post(@path, candidate: attrs()) |> json_response(201)
    assert_response_schema(response, "InvestigationCandidateResponse", LensWeb.ApiSpec.spec())
    candidate = response["candidate"]
    assert {:ok, _} = Ecto.UUID.cast(candidate["id"])
    stored = Repo.get!(Lens.Investigations.Candidate, candidate["id"])
    assert stored.title == "Revenue & margins"
    assert stored.body == "Investigate the change."
    assert stored.details_url == nil
    assert DateTime.compare(stored.published_at, ~U[2026-10-21 00:30:00Z]) == :eq
    assert candidate["published_at"] == DateTime.to_iso8601(stored.published_at)
  end

  test "rejects missing fields, wrong types, excessive text and invalid URLs without inserting" do
    invalid = [
      %{},
      attrs(%{title: "  "}),
      attrs(%{body: nil}),
      attrs(%{title: 42}),
      attrs(%{published_at: "not-a-time"}),
      attrs(%{published_at: nil}),
      attrs(%{published_at: "2026-10-21T09:30:00"}),
      attrs(%{title: String.duplicate("a", 256)}),
      attrs(%{body: String.duplicate("a", 4001)}),
      attrs(%{details_url: String.duplicate("a", 2049)}),
      attrs(%{details_url: "javascript:alert(1)"}),
      attrs(%{details_url: "https://user:password@example.com/"}),
      attrs(%{details_url: "https://example.com/a b"}),
      attrs(%{details_url: "http://example.com:invalid/"}),
      attrs(%{body: "bad\u0001text"}),
      attrs(%{title: "bad\uFFFEtext"})
    ]

    for attributes <- invalid do
      response = build_conn() |> post(@path, candidate: attributes) |> json_response(422)
      assert map_size(response["errors"]) > 0
      assert_response_schema(response, "ValidationErrorsResponse", LensWeb.ApiSpec.spec())
    end

    for payload <- [%{}, %{candidate: nil}, %{candidate: []}, %{candidate: "text"}] do
      response =
        build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(@path, Jason.encode!(payload))
        |> json_response(422)

      assert response["errors"]["candidate"] == ["must be an object"]
    end

    assert Repo.aggregate(Lens.Investigations.Candidate, :count) == 0
  end

  test "accepts Unicode at field limits and preserves plain text and an optional link" do
    attributes =
      attrs(%{
        title: String.duplicate("界", 255),
        body: String.duplicate("界", 3998) <> "\n🦊",
        details_url: "https://example.com/" <> String.duplicate("a", 2028)
      })

    response = build_conn() |> post(@path, candidate: attributes) |> json_response(201)
    candidate = response["candidate"]
    assert candidate["title"] == attributes.title
    assert candidate["body"] == attributes.body
    assert candidate["details_url"] == attributes.details_url
  end

  test "OpenAPI documents registration only and RSS content type" do
    document = LensWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()
    assert document["paths"][@path]["post"]["requestBody"]["required"]

    assert document["paths"]["/feeds/investigation-candidates.rss"]["get"]["responses"]["200"][
             "content"
           ]["application/rss+xml"]

    refute Map.has_key?(document["paths"], @path <> "/{id}")
  end

  test "each registration has its own identity and client IDs are ignored" do
    first = build_conn() |> post(@path, candidate: attrs()) |> json_response(201)

    second =
      build_conn()
      |> post(@path, candidate: attrs(%{id: first["candidate"]["id"]}))
      |> json_response(201)

    refute first["candidate"]["id"] == second["candidate"]["id"]
    assert Repo.aggregate(Lens.Investigations.Candidate, :count) == 2
  end
end
