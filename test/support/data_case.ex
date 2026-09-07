defmodule Lens.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Lens.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Lens.DataCase
    end
  end

  setup tags do
    Lens.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Lens.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, message ->
        String.replace(message, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
