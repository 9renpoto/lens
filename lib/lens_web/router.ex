defmodule LensWeb.Router do
  use LensWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", LensWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
    get("/ready", HealthController, :ready)
    resources("/sources", SourceController, only: [:index, :show, :create])
    patch("/sources/:id", SourceController, :update)
    put("/sources/:id", SourceController, :replace)
    get("/search", SearchController, :index)
    get("/documents/:id", SearchController, :show_document)
  end
end
