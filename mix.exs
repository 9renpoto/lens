defmodule Lens.MixProject do
  use Mix.Project

  def project do
    [
      app: :lens,
      version: "0.1.0-dev",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.lcov": :test],
      dialyzer: [plt_add_apps: [:ex_unit, :mix]],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Lens.Application, []},
      extra_applications: [:inets, :logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:castore, "~> 1.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.12"},
      {:excoveralls, "~> 0.18", only: :test},
      {:jason, "~> 1.4"},
      {:open_api_spex, "~> 3.22"},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.6"},
      {:postgrex, "~> 0.21"},
      {:req, "~> 0.7"},
      {:saxy, "~> 1.6"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
