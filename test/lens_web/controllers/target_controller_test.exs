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
        market: "TSE Prime",
        display_name: "Toyota Motor Corp (Synthetic)",
        sector: "Transportation Equipment",
        tags: ["automotive", "large-cap"],
        source_reference: "EDINET filing #12345",
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
      assert target["market"] == "TSE Prime"
      assert target["display_name"] == "Toyota Motor Corp (Synthetic)"
      assert target["sector"] == "Transportation Equipment"
      assert target["tags"] == ["automotive", "large-cap"]
      assert target["active"] == true
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

    test "documents membership index-name bounds" do
      schema = Map.fetch!(ApiSpec.spec().components.schemas, "MembershipAttributes")

      assert schema.properties.index_name.minLength == 1
      assert schema.properties.index_name.maxLength == 100
      assert schema.properties.index_name.pattern == "\\S"
    end
  end

  describe "GET /api/targets" do
    test "lists targets and supports as_of filter" do
      attrs1 = valid_target_attrs()
      attrs2 = valid_target_attrs()

      {:ok, t1} = Analysis.create_target(attrs1)
      {:ok, t2} = Analysis.create_target(attrs2)

      {:ok, _} =
        Analysis.create_membership(t1, %{
          effective_from: ~D[2020-01-01],
          effective_to: ~D[2023-12-31]
        })

      {:ok, _} = Analysis.create_membership(t2, %{effective_from: ~D[2022-01-01]})

      conn_all = build_conn() |> get("/api/targets")
      response_all = json_response(conn_all, 200)
      assert %{"targets" => targets_all} = response_all
      assert length(targets_all) >= 2
      assert_response_schema(response_all, "TargetsResponse", ApiSpec.spec())

      conn_as_of = build_conn() |> get("/api/targets?as_of=2024-06-01")
      response_as_of = json_response(conn_as_of, 200)
      assert %{"targets" => targets_as_of} = response_as_of
      assert_response_schema(response_as_of, "TargetsResponse", ApiSpec.spec())

      codes = Enum.map(targets_as_of, & &1["security_code"])
      refute attrs1.security_code in codes
      assert attrs2.security_code in codes
    end

    test "returns 422 for an invalid as_of value" do
      conn = build_conn() |> get("/api/targets?as_of=not-a-date")

      response = json_response(conn, 422)
      assert response["errors"]["as_of"] == ["is invalid"]
      assert_response_schema(response, "ValidationErrorsResponse", ApiSpec.spec())
    end
  end

  describe "GET /api/targets/:id" do
    test "shows target with memberships" do
      attrs = valid_target_attrs()
      {:ok, target} = Analysis.create_target(attrs)
      {:ok, _m} = Analysis.create_membership(target, %{effective_from: ~D[2021-01-01]})

      conn = build_conn() |> get("/api/targets/#{target.id}")
      response = json_response(conn, 200)
      assert %{"target" => res_target} = response
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      assert res_target["id"] == target.id
      assert res_target["security_code"] == attrs.security_code
      assert length(res_target["memberships"]) == 1
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
      assert deactivated["active"] == false
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      conn_404 = build_conn() |> post("/api/targets/#{missing_id()}/deactivate")
      assert json_response(conn_404, 404)["error"] == "not_found"
    end
  end

  describe "Membership intervals endpoints" do
    setup do
      {:ok, target} = Analysis.create_target(valid_target_attrs())
      %{target: target}
    end

    test "POST and GET /api/targets/:target_id/memberships and 404s", %{target: target} do
      conn_create =
        build_conn()
        |> post("/api/targets/#{target.id}/memberships",
          membership: %{
            effective_from: "2020-01-01",
            effective_to: "2023-12-31",
            source_reference: "Official Review 2020"
          }
        )

      response_create = json_response(conn_create, 201)
      assert %{"membership" => membership} = response_create
      assert membership["effective_from"] == "2020-01-01"
      assert membership["effective_to"] == "2023-12-31"
      assert membership["index_name"] == "nikkei_225"
      assert_response_schema(response_create, "MembershipResponse", ApiSpec.spec())

      conn_list = build_conn() |> get("/api/targets/#{target.id}/memberships")
      response_list = json_response(conn_list, 200)
      assert %{"memberships" => memberships} = response_list
      assert length(memberships) == 1
      assert_response_schema(response_list, "MembershipsResponse", ApiSpec.spec())

      conn_list_404 = build_conn() |> get("/api/targets/#{missing_id()}/memberships")
      assert json_response(conn_list_404, 404)["error"] == "not_found"

      conn_create_404 =
        build_conn()
        |> post("/api/targets/#{missing_id()}/memberships",
          membership: %{effective_from: "2020-01-01"}
        )

      assert json_response(conn_create_404, 404)["error"] == "not_found"
    end

    test "returns 422 when membership index_name contains only whitespace", %{target: target} do
      response =
        build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(
          "/api/targets/#{target.id}/memberships",
          Jason.encode!(%{membership: %{index_name: "   ", effective_from: "2020-01-01"}})
        )
        |> json_response(422)

      assert response["errors"]["index_name"] == ["can't be blank"]
      assert_response_schema(response, "ValidationErrorsResponse", ApiSpec.spec())
    end

    test "returns 422 when creating overlapping membership", %{target: target} do
      {:ok, _} =
        Analysis.create_membership(target, %{
          effective_from: ~D[2020-01-01],
          effective_to: ~D[2023-12-31]
        })

      conn =
        build_conn()
        |> post("/api/targets/#{target.id}/memberships",
          membership: %{
            effective_from: "2022-01-01",
            effective_to: "2024-12-31"
          }
        )

      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert errors["effective_from"] != nil
      assert_response_schema(response, "ValidationErrorsResponse", ApiSpec.spec())
    end

    test "returns 422 for non-object membership attributes", %{target: target} do
      create_response =
        build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(
          "/api/targets/#{target.id}/memberships",
          Jason.encode!(%{membership: []})
        )
        |> json_response(422)

      assert create_response["errors"]["membership"] == ["must be an object"]
      assert_response_schema(create_response, "ValidationErrorsResponse", ApiSpec.spec())

      {:ok, membership} =
        Analysis.create_membership(target, %{effective_from: ~D[2020-01-01]})

      update_response =
        build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> patch(
          "/api/targets/#{target.id}/memberships/#{membership.id}",
          Jason.encode!(%{membership: []})
        )
        |> json_response(422)

      assert update_response["errors"]["membership"] == ["must be an object"]
      assert_response_schema(update_response, "ValidationErrorsResponse", ApiSpec.spec())
    end

    test "PATCH closes an open membership interval", %{target: target} do
      {:ok, membership} =
        Analysis.create_membership(target, %{effective_from: ~D[2020-01-01]})

      conn =
        build_conn()
        |> patch("/api/targets/#{target.id}/memberships/#{membership.id}",
          membership: %{effective_to: "2024-09-30"}
        )

      response = json_response(conn, 200)
      assert response["membership"]["effective_to"] == "2024-09-30"
      assert_response_schema(response, "MembershipResponse", ApiSpec.spec())
    end

    test "PATCH ignores membership identity and interval-start fields", %{target: target} do
      {:ok, other_target} = Analysis.create_target(valid_target_attrs())

      {:ok, membership} =
        Analysis.create_membership(target, %{effective_from: ~D[2020-01-01]})

      conn =
        build_conn()
        |> patch("/api/targets/#{target.id}/memberships/#{membership.id}",
          membership: %{
            target_id: other_target.id,
            index_name: "topix",
            effective_from: "2021-01-01",
            effective_to: "2024-09-30"
          }
        )

      response = json_response(conn, 200)
      assert response["membership"]["target_id"] == target.id
      assert response["membership"]["index_name"] == "nikkei_225"
      assert response["membership"]["effective_from"] == "2020-01-01"
      assert response["membership"]["effective_to"] == "2024-09-30"
    end
  end

  defp missing_id, do: "00000000-0000-0000-0000-000000000000"
end
