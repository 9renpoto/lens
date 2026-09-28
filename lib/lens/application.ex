defmodule Lens.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    require_endpoint_secret!()

    children = [
      Lens.Repo,
      {Phoenix.PubSub, name: Lens.PubSub},
      {Task.Supervisor, name: Lens.Ingestion.TaskSupervisor},
      {Lens.Ingestion.Scheduler, []},
      LensWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Lens.Supervisor)
  end

  defp require_endpoint_secret! do
    endpoint_config = Application.get_env(:lens, LensWeb.Endpoint, [])

    if Keyword.get(endpoint_config, :server, false) do
      System.fetch_env!("SECRET_KEY_BASE")
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    LensWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
