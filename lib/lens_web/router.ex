defmodule LensWeb.Router do
  use LensWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", LensWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
    resources("/sources", SourceController, only: [:index, :show, :create, :update])
    get("/search", SearchController, :index)
    get("/documents/:id", SearchController, :show_document)
  end
end
