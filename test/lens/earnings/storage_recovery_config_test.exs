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

  test "retired recovery configuration has no effect and no poller is supervised" do
    for value <- ["true", "false", "obsolete-value"] do
      System.put_env("LENS_STORAGE_RECOVERY_ENABLED", value)
      config = Config.Reader.read!("config/runtime.exs", env: :test)
      refute get_in(config, [:lens, Lens.Earnings.StorageRecovery])
    end

    refute Enum.any?(Supervisor.which_children(Lens.Supervisor), fn {id, _, _, _} ->
             id == Lens.Earnings.StorageRecovery
           end)
  end
end
