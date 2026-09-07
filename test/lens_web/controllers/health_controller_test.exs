defmodule LensWeb.HealthControllerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint LensWeb.Endpoint

  test "reports application health" do
    conn = get(build_conn(), "/api/health")

    assert %{"status" => "ok"} = json_response(conn, 200)
  end
end
