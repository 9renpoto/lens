defmodule LensWeb.HealthControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest

  @endpoint LensWeb.Endpoint

  test "reports application health" do
    conn = get(build_conn(), "/api/health")

    assert %{"status" => "ok"} = json_response(conn, 200)
  end

  test "reports ready when PostgreSQL is available" do
    conn = get(build_conn(), "/api/ready")

    assert %{"status" => "ready"} = json_response(conn, 200)
  end
end
