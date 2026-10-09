defmodule Lens.Earnings.StorageRecoveryConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("LENS_STORAGE_RECOVERY_ENABLED")
    System.delete_env("LENS_STORAGE_RECOVERY_ENABLED")

    on_exit(fn ->
      if previous,
        do: System.put_env("LENS_STORAGE_RECOVERY_ENABLED", previous),
        else: System.delete_env("LENS_STORAGE_RECOVERY_ENABLED")
    end)

    :ok
  end

  test "poller activation is explicit and independent of RustFS configuration" do
    config = Config.Reader.read!("config/runtime.exs", env: :test)
    refute get_in(config, [:lens, Lens.Earnings.StorageRecovery])
    System.put_env("LENS_STORAGE_RECOVERY_ENABLED", "true")
    config = Config.Reader.read!("config/runtime.exs", env: :test)
    assert get_in(config, [:lens, Lens.Earnings.StorageRecovery]) == [enabled: true]
    System.put_env("LENS_STORAGE_RECOVERY_ENABLED", "false")
    config = Config.Reader.read!("config/runtime.exs", env: :test)
    assert get_in(config, [:lens, Lens.Earnings.StorageRecovery]) == [enabled: false]
  end

  test "invalid activation value fails without echoing environment contents" do
    System.put_env("LENS_STORAGE_RECOVERY_ENABLED", "invalid-private-value")

    assert_raise ArgumentError, "invalid storage recovery configuration", fn ->
      Config.Reader.read!("config/runtime.exs", env: :test)
    end
  end
end
