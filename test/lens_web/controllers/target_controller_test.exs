defmodule LensWeb.TargetControllerTest do
  use Lens.DataCase

  import OpenApiSpex.TestAssertions
  import Phoenix.ConnTest

  alias Lens.Analysis
  alias LensWeb.ApiSpec

  @endpoint LensWeb.Endpoint

  defp valid_target_attrs(custom \\ %{}) do
    Map.merge(
      %{
        security_code: "CODE-#{System.unique_integer([:positive])}",
        market: "Fictional Exchange",
        display_name: "Example Components",
        sector: "Transportation Equipment",
        tags: ["automotive", "large-cap"],
        source_reference: "Synthetic issuer profile",
        verified_at: "2024-01-15T10:00:00Z"
      },
      custom
    )
  end

  describe "POST /api/targets" do
    test "creates a target with valid attributes" do
      attrs = valid_target_attrs()

      conn =
        build_conn()
        |> post("/api/targets", target: attrs)

      response = json_response(conn, 201)
      assert %{"target" => target} = response
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      assert target["security_code"] == attrs.security_code
      assert target["market"] == "Fictional Exchange"
      assert target["display_name"] == "Example Components"
      assert target["sector"] == "Transportation Equipment"
      assert target["tags"] == ["automotive", "large-cap"]
      assert target["active"] == true
      refute Map.has_key?(target, "memberships")
    end

    test "returns 422 for invalid attributes or duplicate security code" do
      conn1 = build_conn() |> post("/api/targets", target: %{})
      response1 = json_response(conn1, 422)
      assert %{"errors" => errors} = response1
      assert errors["security_code"] != nil
      assert_response_schema(response1, "ValidationErrorsResponse", ApiSpec.spec())

      attrs = valid_target_attrs()
      assert {:ok, _} = Analysis.create_target(attrs)

      conn2 = build_conn() |> post("/api/targets", target: attrs)
      response2 = json_response(conn2, 422)
      assert %{"errors" => errors2} = response2
      assert errors2["security_code"] != nil
      assert_response_schema(response2, "ValidationErrorsResponse", ApiSpec.spec())
    end

    test "returns 422 when non-null default fields are explicitly null" do
      for field <- [:tags, :active] do
        conn = build_conn() |> post("/api/targets", target: valid_target_attrs(%{field => nil}))
        assert json_response(conn, 422)["errors"][Atom.to_string(field)] != nil
      end
    end

    test "PATCH rejects blank active and tags values instead of applying defaults" do
      {:ok, target} = Analysis.create_target(valid_target_attrs(%{active: false}))

      for field <- [:active, :tags] do
        response =
          build_conn()
          |> Plug.Conn.put_req_header("content-type", "application/json")
          |> patch("/api/targets/#{target.id}", Jason.encode!(%{target: %{field => ""}}))
          |> json_response(422)

        assert response["errors"][Atom.to_string(field)] != nil
      end

      assert {:ok, unchanged} = Analysis.fetch_target(target.id)
      assert unchanged.active == false
      assert unchanged.tags == ["automotive", "large-cap"]
    end

    test "returns 422 when display name exceeds the database character limit by codepoint" do
      create_conn =
        build_conn()
        |> post(
          "/api/targets",
          target: valid_target_attrs(%{display_name: String.duplicate("e\u0301", 128)})
        )

      create_response = json_response(create_conn, 422)
      assert create_response["errors"]["display_name"] != nil
      assert_response_schema(create_response, "ValidationErrorsResponse", ApiSpec.spec())

      {:ok, target} = Analysis.create_target(valid_target_attrs())

      update_conn =
        build_conn()
        |> patch("/api/targets/#{target.id}",
          target: %{display_name: String.duplicate("e\u0301", 128)}
        )

      update_response = json_response(update_conn, 422)
      assert update_response["errors"]["display_name"] != nil
      assert_response_schema(update_response, "ValidationErrorsResponse", ApiSpec.spec())
    end

    test "returns 422 for non-object target attributes" do
      create_response =
        build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post("/api/targets", Jason.encode!(%{target: []}))
        |> json_response(422)

      assert create_response["errors"]["target"] == ["must be an object"]
      assert_response_schema(create_response, "ValidationErrorsResponse", ApiSpec.spec())

      {:ok, target} = Analysis.create_target(valid_target_attrs())

      update_response =
        build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> patch("/api/targets/#{target.id}", Jason.encode!(%{target: []}))
        |> json_response(422)

      assert update_response["errors"]["target"] == ["must be an object"]
      assert_response_schema(update_response, "ValidationErrorsResponse", ApiSpec.spec())
    end

    test "documents required create attributes" do
      schema = Map.fetch!(ApiSpec.spec().components.schemas, "CreateTargetAttributes")

      assert Enum.sort(schema.required) ==
               Enum.sort([:security_code, :market, :display_name, :sector])
    end

    test "documents the target wrapper as required for updates" do
      schema = Map.fetch!(ApiSpec.spec().components.schemas, "UpdateTargetRequest")

      assert schema.required == [:target]
    end

    test "documents the active default only for target creation" do
      schemas = ApiSpec.spec().components.schemas
      create_schema = Map.fetch!(schemas, "CreateTargetAttributes")
      update_schema = Map.fetch!(schemas, "TargetAttributes")

      assert create_schema.properties.active.default == true
      assert update_schema.properties.active.default == nil
    end

    test "documents target field bounds for creation and updates" do
      schemas = ApiSpec.spec().components.schemas

      for schema_name <- ["CreateTargetAttributes", "TargetAttributes"] do
        properties = Map.fetch!(schemas, schema_name).properties

        assert properties.security_code.minLength == 1
        assert properties.security_code.maxLength == 50
        assert properties.security_code.pattern == "\\S"
        assert properties.market.minLength == 1
        assert properties.market.maxLength == 100
        assert properties.market.pattern == "\\S"
        assert properties.display_name.minLength == 1
        assert properties.display_name.maxLength == 255
        assert properties.display_name.pattern == "\\S"
        assert properties.sector.minLength == 1
        assert properties.sector.maxLength == 100
        assert properties.sector.pattern == "\\S"
        assert properties.tags.maxItems == 10
        assert properties.tags.items.maxLength == 50
      end
    end
  end

  describe "GET /api/targets" do
    test "lists active and inactive targets in security-code order" do
      {:ok, inactive} =
        Analysis.create_target(valid_target_attrs(%{security_code: "002-FICT", active: false}))

      {:ok, active} = Analysis.create_target(valid_target_attrs(%{security_code: "001-FICT"}))

      response = build_conn() |> get("/api/targets") |> json_response(200)
      assert_response_schema(response, "TargetsResponse", ApiSpec.spec())

      assert [%{"id" => active_id, "active" => true}, %{"id" => inactive_id, "active" => false}] =
               response["targets"]

      assert active_id == active.id
      assert inactive_id == inactive.id
      refute Enum.any?(response["targets"], &Map.has_key?(&1, "memberships"))
    end

    test "ignores the retired as_of query parameter" do
      {:ok, target} = Analysis.create_target(valid_target_attrs())

      response = build_conn() |> get("/api/targets?as_of=2024-06-01") |> json_response(200)
      assert [%{"id" => id}] = response["targets"]
      assert id == target.id
    end
  end

  describe "GET /api/targets/:id" do
    test "shows the existing target identity without membership data" do
      attrs = valid_target_attrs(%{security_code: "001-FICT"})
      {:ok, target} = Analysis.create_target(attrs)

      conn = build_conn() |> get("/api/targets/#{target.id}")
      response = json_response(conn, 200)
      assert %{"target" => res_target} = response
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      assert res_target["id"] == target.id
      assert res_target["security_code"] == attrs.security_code
      refute Map.has_key?(res_target, "memberships")
    end

    test "returns 404 when target is not found" do
      conn = build_conn() |> get("/api/targets/#{missing_id()}")
      response = json_response(conn, 404)
      assert response["error"] == "not_found"
      assert_response_schema(response, "ErrorResponse", ApiSpec.spec())
    end
  end

  describe "PATCH /api/targets/:id" do
    test "updates target attributes and handles validation error / 404" do
      {:ok, target} = Analysis.create_target(valid_target_attrs())

      conn =
        build_conn()
        |> patch("/api/targets/#{target.id}", target: %{display_name: "New Name (Synthetic)"})

      response = json_response(conn, 200)
      assert %{"target" => updated} = response
      assert updated["id"] == target.id
      assert updated["security_code"] == target.security_code
      refute Map.has_key?(updated, "memberships")
      assert updated["display_name"] == "New Name (Synthetic)"
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      conn_err = build_conn() |> patch("/api/targets/#{target.id}", target: %{market: ""})
      assert json_response(conn_err, 422)["errors"]["market"] != nil

      conn_404 =
        build_conn()
        |> patch("/api/targets/#{missing_id()}", target: %{display_name: "X"})

      assert json_response(conn_404, 404)["error"] == "not_found"
    end
  end

  describe "POST /api/targets/:id/deactivate" do
    test "deactivates target non-destructively and handles 404" do
      {:ok, target} = Analysis.create_target(valid_target_attrs())
      assert target.active == true

      conn = build_conn() |> post("/api/targets/#{target.id}/deactivate")
      response = json_response(conn, 200)
      assert %{"target" => deactivated} = response
      assert deactivated["id"] == target.id
      assert deactivated["security_code"] == target.security_code
      assert deactivated["active"] == false
      refute Map.has_key?(deactivated, "memberships")

      fetched = build_conn() |> get("/api/targets/#{target.id}") |> json_response(200)
      assert fetched["target"] == deactivated
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      conn_404 = build_conn() |> post("/api/targets/#{missing_id()}/deactivate")
      assert json_response(conn_404, 404)["error"] == "not_found"
    end
  end

  defp missing_id, do: "00000000-0000-0000-0000-000000000000"
end
