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
    Application.ensure_all_started(:lens)
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Lens.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, message ->
        val_str =
          if is_binary(value) or is_atom(value) or is_number(value),
            do: to_string(value),
            else: inspect(value)

        String.replace(message, "%{#{key}}", val_str)
      end)
    end)
  end
end
