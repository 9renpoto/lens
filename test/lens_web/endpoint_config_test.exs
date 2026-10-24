defmodule LensWeb.EndpointConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("PORT")
    System.delete_env("PORT")

    on_exit(fn ->
      if previous, do: System.put_env("PORT", previous), else: System.delete_env("PORT")
    end)

    :ok
  end

  test "development links use the documented loopback origin" do
    endpoint = development_endpoint()

    assert endpoint[:http][:port] == 4000
    assert endpoint[:url] == [scheme: "http", host: "127.0.0.1", port: 4000]
  end

  test "development links follow a custom listening port" do
    System.put_env("PORT", "4187")
    endpoint = development_endpoint()

    assert endpoint[:http][:port] == 4187
    assert endpoint[:url] == [scheme: "http", host: "127.0.0.1", port: 4187]
  end

  defp development_endpoint do
    "config/config.exs"
    |> Config.Reader.read!(env: :dev)
    |> get_in([:lens, LensWeb.Endpoint])
  end
end
