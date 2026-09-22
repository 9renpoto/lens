defmodule LensWeb.TargetControllerTest do
  use Lens.DataCase

  import OpenApiSpex.TestAssertions
  import Phoenix.ConnTest

  alias Lens.Analysis
  alias LensWeb.ApiSpec

  @endpoint LensWeb.Endpoint

  @valid_target_attrs %{
    security_code: "7203",
    market: "TSE Prime",
    display_name: "Toyota Motor Corp (Synthetic)",
    sector: "Transportation Equipment",
    tags: ["automotive", "large-cap"],
    source_reference: "EDINET filing #12345",
    verified_at: "2024-01-15T10:00:00Z"
  }

  describe "POST /api/targets" do
    test "creates a target with valid attributes" do
      conn =
        build_conn()
        |> post("/api/targets", target: @valid_target_attrs)

      response = json_response(conn, 201)
      assert %{"target" => target} = response
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      assert target["security_code"] == "7203"
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

      assert {:ok, _} =
               Analysis.create_target(Map.put(@valid_target_attrs, :security_code, "7203"))

      conn2 = build_conn() |> post("/api/targets", target: @valid_target_attrs)
      response2 = json_response(conn2, 422)
      assert %{"errors" => errors2} = response2
      assert errors2["security_code"] != nil
      assert_response_schema(response2, "ValidationErrorsResponse", ApiSpec.spec())
    end
  end

  describe "GET /api/targets" do
    test "lists targets and supports as_of filter" do
      {:ok, t1} = Analysis.create_target(%{@valid_target_attrs | security_code: "9983"})
      {:ok, t2} = Analysis.create_target(%{@valid_target_attrs | security_code: "9984"})

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
      refute "9983" in codes
      assert "9984" in codes
    end
  end

  describe "GET /api/targets/:id" do
    test "shows target with memberships" do
      {:ok, target} = Analysis.create_target(@valid_target_attrs)
      {:ok, _m} = Analysis.create_membership(target, %{effective_from: ~D[2021-01-01]})

      conn = build_conn() |> get("/api/targets/#{target.id}")
      response = json_response(conn, 200)
      assert %{"target" => res_target} = response
      assert_response_schema(response, "TargetResponse", ApiSpec.spec())

      assert res_target["id"] == target.id
      assert res_target["security_code"] == "7203"
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
      {:ok, target} = Analysis.create_target(@valid_target_attrs)

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
        build_conn() |> patch("/api/targets/#{missing_id()}", target: %{display_name: "X"})

      assert json_response(conn_404, 404)["error"] == "not_found"
    end
  end

  describe "POST /api/targets/:id/deactivate" do
    test "deactivates target non-destructively and handles 404" do
      {:ok, target} = Analysis.create_target(@valid_target_attrs)
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
      {:ok, target} = Analysis.create_target(@valid_target_attrs)
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
  end

  defp missing_id, do: "00000000-0000-0000-0000-000000000000"
end
