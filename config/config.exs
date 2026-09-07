import Config

config :lens,
  ecto_repos: [Lens.Repo]

config :lens, LensWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: LensWeb.ErrorJSON], layout: false],
  pubsub_server: Lens.PubSub

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
