import Config

config :lens,
  ecto_repos: [Lens.Repo]

config :sentry,
  before_send: {Lens.ErrorReporter, :before_send},
  enable_source_code_context: false

config :lens, LensWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: LensWeb.ErrorJSON], layout: false],
  pubsub_server: Lens.PubSub

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :source_id, :outcome, :duration_ms, :valid_entries, :invalid_entries]

import_config "#{config_env()}.exs"
