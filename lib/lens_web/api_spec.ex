defmodule LensWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification generated from Lens HTTP controllers and schemas.
  """

  alias OpenApiSpex.{Info, OpenApi, Paths}

  @behaviour OpenApi

  @impl OpenApi
  @spec spec() :: OpenApi.t()
  def spec do
    %OpenApi{
      openapi: "3.0.3",
      info: %Info{
        title: "Lens API",
        version: to_string(Application.spec(:lens, :vsn)),
        description: "The HTTP API for a self-hosted Lens deployment."
      },
      paths: Paths.from_router(LensWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
