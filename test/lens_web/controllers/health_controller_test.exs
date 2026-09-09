defmodule LensWeb.HealthControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest
  import OpenApiSpex.TestAssertions

  alias LensWeb.ApiSpec
  @endpoint LensWeb.Endpoint

  test "reports application health" do
    conn = get(build_conn(), "/api/health")

    response = json_response(conn, 200)
    assert %{"status" => "ok"} = response
    assert_response_schema(response, "HealthResponse", ApiSpec.spec())
  end

  test "reports ready when PostgreSQL is available" do
    conn = get(build_conn(), "/api/ready")

    response = json_response(conn, 200)
    assert %{"status" => "ready"} = response
    assert_response_schema(response, "ReadyResponse", ApiSpec.spec())
  end
end
