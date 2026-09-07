defmodule LensWeb.HealthController do
  use LensWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
