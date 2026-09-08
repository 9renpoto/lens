defmodule Lens.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Lens.Repo,
      {Phoenix.PubSub, name: Lens.PubSub},
      {Task.Supervisor, name: Lens.Ingestion.TaskSupervisor},
      {Lens.Ingestion.Scheduler, []},
      LensWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Lens.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LensWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
