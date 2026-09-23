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
    get("/documents/:id/provenance", SearchController, :show_provenance)

    resources("/targets", TargetController, only: [:index, :show, :create])
    patch("/targets/:id", TargetController, :update)
    post("/targets/:id/deactivate", TargetController, :deactivate)
    get("/targets/:target_id/memberships", TargetController, :index_memberships)
    post("/targets/:target_id/memberships", TargetController, :create_membership)

    patch(
      "/targets/:target_id/memberships/:id",
      TargetController,
      :update_membership
    )
  end

  scope "/", LensWeb do
    get("/dashboard", DashboardController, :show)
  end
end
