defmodule LensWeb.Router do
  use LensWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", LensWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
    resources("/sources", SourceController, only: [:index, :show, :create, :update])
  end
end
