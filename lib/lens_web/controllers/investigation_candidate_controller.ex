defmodule LensWeb.InvestigationCandidateController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Investigations

  alias LensWeb.ApiSchemas.{
    InvestigationCandidateRequest,
    InvestigationCandidateResponse,
    ValidationErrorsResponse
  }

  tags(["Investigation candidates"])

  operation :create,
    summary: "Register an investigation candidate",
    request_body:
      {"Candidate attributes", "application/json", InvestigationCandidateRequest, required: true},
    responses: [
      created: {"Registered candidate", "application/json", InvestigationCandidateResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  def create(conn, %{"candidate" => attrs}) when is_map(attrs) do
    case Investigations.register_candidate(attrs) do
      {:ok, candidate} ->
        conn
        |> put_status(:created)
        |> json(%{
          candidate: Map.take(candidate, [:id, :title, :body, :details_url, :published_at])
        })

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
            Enum.reduce(options, message, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{candidate: ["must be an object"]}})
  end
end
