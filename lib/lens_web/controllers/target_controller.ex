defmodule LensWeb.TargetController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Analysis
  alias OpenApiSpex.Schema

  alias LensWeb.ApiSchemas.{
    CreateMembershipRequest,
    CreateTargetRequest,
    ErrorResponse,
    MembershipResponse,
    MembershipsResponse,
    TargetResponse,
    TargetsResponse,
    UpdateMembershipRequest,
    UpdateTargetRequest,
    ValidationErrorsResponse
  }

  tags(["Targets"])

  operation :index,
    summary: "List analysis targets",
    parameters: [
      as_of: [
        in: :query,
        description: "Filter targets active as of date (YYYY-MM-DD)",
        schema: %Schema{type: :string, format: :date}
      ]
    ],
    responses: [
      ok: {"Analysis targets", "application/json", TargetsResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :show,
    summary: "Get an analysis target",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Analysis target", "application/json", TargetResponse},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  operation :create,
    summary: "Create an analysis target",
    request_body: {"Target attributes", "application/json", CreateTargetRequest},
    responses: [
      created: {"Created target", "application/json", TargetResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :update,
    summary: "Update an analysis target",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    request_body: {"Target changes", "application/json", UpdateTargetRequest},
    responses: [
      ok: {"Updated target", "application/json", TargetResponse},
      not_found: {"Target not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :deactivate,
    summary: "Deactivate an analysis target",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Deactivated target", "application/json", TargetResponse},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  operation :index_memberships,
    summary: "List membership intervals for a target",
    parameters: [target_id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Target membership intervals", "application/json", MembershipsResponse},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  operation :create_membership,
    summary: "Create a membership interval for a target",
    parameters: [target_id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    request_body: {"Membership attributes", "application/json", CreateMembershipRequest},
    responses: [
      created: {"Created membership interval", "application/json", MembershipResponse},
      not_found: {"Target not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :update_membership,
    summary: "Update a membership interval",
    parameters: [
      target_id: [in: :path, schema: %Schema{type: :string, format: :uuid}],
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}]
    ],
    request_body: {"Membership changes", "application/json", UpdateMembershipRequest},
    responses: [
      ok: {"Updated membership interval", "application/json", MembershipResponse},
      not_found: {"Membership not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  def index(conn, params) do
    opts = if as_of = params["as_of"], do: [as_of: as_of], else: []

    case Analysis.list_targets(opts) do
      {:error, :invalid_as_of} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: %{as_of: ["is invalid"]}})

      targets ->
        json(conn, %{targets: Enum.map(targets, &target_json/1)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Analysis.fetch_target(id) do
      {:ok, target} -> json(conn, %{target: target_json(target)})
      :error -> not_found(conn)
    end
  end

  def create(conn, %{"target" => attrs}) do
    case Analysis.create_target(attrs) do
      {:ok, target} -> conn |> put_status(:created) |> json(%{target: target_json(target)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id, "target" => attrs}) do
    case Analysis.fetch_target(id) do
      {:ok, target} ->
        case Analysis.update_target(target, attrs) do
          {:ok, target} -> json(conn, %{target: target_json(target)})
          {:error, changeset} -> validation_error(conn, changeset)
        end

      :error ->
        not_found(conn)
    end
  end

  def deactivate(conn, %{"id" => id}) do
    case Analysis.fetch_target(id) do
      {:ok, target} ->
        case Analysis.deactivate_target(target) do
          {:ok, target} -> json(conn, %{target: target_json(target)})
          {:error, changeset} -> validation_error(conn, changeset)
        end

      :error ->
        not_found(conn)
    end
  end

  def index_memberships(conn, %{"target_id" => target_id}) do
    case Analysis.fetch_target(target_id) do
      {:ok, _target} ->
        memberships = Analysis.list_memberships(target_id)
        json(conn, %{memberships: Enum.map(memberships, &membership_json/1)})

      :error ->
        not_found(conn)
    end
  end

  def create_membership(conn, %{"target_id" => target_id, "membership" => attrs}) do
    case Analysis.fetch_target(target_id) do
      {:ok, target} ->
        case Analysis.create_membership(target, attrs) do
          {:ok, membership} ->
            conn |> put_status(:created) |> json(%{membership: membership_json(membership)})

          {:error, changeset} ->
            validation_error(conn, changeset)
        end

      :error ->
        not_found(conn)
    end
  end

  def update_membership(conn, %{
        "target_id" => target_id,
        "id" => id,
        "membership" => attrs
      }) do
    case Analysis.fetch_membership(target_id, id) do
      {:ok, membership} ->
        case Analysis.update_membership(membership, attrs) do
          {:ok, membership} -> json(conn, %{membership: membership_json(membership)})
          {:error, changeset} -> validation_error(conn, changeset)
        end

      :error ->
        not_found(conn)
    end
  end

  defp validation_error(conn, changeset) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors(changeset)})
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  defp target_json(target) do
    base =
      Map.take(target, [
        :id,
        :security_code,
        :market,
        :display_name,
        :sector,
        :tags,
        :active,
        :source_reference,
        :verified_at
      ])

    if Ecto.assoc_loaded?(target.memberships) do
      Map.put(base, :memberships, Enum.map(target.memberships, &membership_json/1))
    else
      base
    end
  end

  defp membership_json(membership) do
    Map.take(membership, [
      :id,
      :target_id,
      :index_name,
      :effective_from,
      :effective_to,
      :source_reference,
      :verified_at
    ])
  end

  defp errors(changeset),
    do: Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
end
