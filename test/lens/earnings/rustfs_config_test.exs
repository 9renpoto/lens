defmodule Lens.Earnings.RustFSConfigTest do
  use ExUnit.Case, async: false
  alias Lens.Earnings.RustFS

  @variables ~w(LENS_RUSTFS_ENDPOINT LENS_RUSTFS_BUCKET LENS_RUSTFS_ACCESS_KEY_ID LENS_RUSTFS_SECRET_ACCESS_KEY LENS_RUSTFS_REGION LENS_RUSTFS_TIMEOUT_MS)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)
    config = Application.fetch_env(:lens, RustFS)

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end

      case config do
        {:ok, value} -> Application.put_env(:lens, RustFS, value)
        :error -> Application.delete_env(:lens, RustFS)
      end
    end)

    :ok
  end

  test "runtime environment selects one endpoint and bucket without enabling collection" do
    System.put_env(%{
      "LENS_RUSTFS_ENDPOINT" => "https://rustfs.example.test",
      "LENS_RUSTFS_BUCKET" => "lens-originals",
      "LENS_RUSTFS_ACCESS_KEY_ID" => "test-access",
      "LENS_RUSTFS_SECRET_ACCESS_KEY" => "test-secret",
      "LENS_RUSTFS_REGION" => "us-east-1",
      "LENS_RUSTFS_TIMEOUT_MS" => "1500"
    })

    config = Config.Reader.read!("config/runtime.exs", env: :test)
    options = get_in(config, [:lens, RustFS])
    Application.put_env(:lens, RustFS, options)
    assert {:ok, client} = RustFS.new()
    assert client.endpoint == "https://rustfs.example.test"
    assert client.bucket == "lens-originals"
    assert client.timeout_ms == 1500
    assert Keyword.keys(config[:lens]) == [RustFS]
  end

  test "absent storage environment leaves the existing application unconfigured" do
    config = Config.Reader.read!("config/runtime.exs", env: :test)
    refute get_in(config, [:lens, RustFS])
    Application.delete_env(:lens, RustFS)
    assert RustFS.new() == {:error, :not_configured}
  end

  test "partial or invalid runtime configuration is rejected without including secrets" do
    System.put_env("LENS_RUSTFS_SECRET_ACCESS_KEY", "private-test-secret")

    assert_raise ArgumentError, "invalid RustFS configuration", fn ->
      Config.Reader.read!("config/runtime.exs", env: :test)
    end

    System.put_env(%{
      "LENS_RUSTFS_ENDPOINT" => "https://rustfs.example.test",
      "LENS_RUSTFS_BUCKET" => "lens-originals",
      "LENS_RUSTFS_ACCESS_KEY_ID" => "test-access",
      "LENS_RUSTFS_TIMEOUT_MS" => "infinity"
    })

    assert_raise ArgumentError, "invalid RustFS configuration", fn ->
      Config.Reader.read!("config/runtime.exs", env: :test)
    end
  end
end
