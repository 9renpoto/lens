defmodule Lens.ApplicationTest do
  use ExUnit.Case, async: false

  test "requires SECRET_KEY_BASE when starting the production endpoint" do
    endpoint_config = Application.fetch_env!(:lens, LensWeb.Endpoint)
    previous_secret = System.get_env("SECRET_KEY_BASE")

    Application.put_env(:lens, LensWeb.Endpoint, Keyword.put(endpoint_config, :server, true))
    System.delete_env("SECRET_KEY_BASE")

    on_exit(fn ->
      Application.put_env(:lens, LensWeb.Endpoint, endpoint_config)

      if is_nil(previous_secret) do
        System.delete_env("SECRET_KEY_BASE")
      else
        System.put_env("SECRET_KEY_BASE", previous_secret)
      end
    end)

    assert_raise System.EnvError, ~r/SECRET_KEY_BASE/, fn ->
      Lens.Application.start(:normal, [])
    end
  end
end
