defmodule Lens.Ingestion.Result do
  @enforce_keys [:outcome]
  defstruct [:outcome, :status, :valid_entries, :invalid_entries, :error]
end
