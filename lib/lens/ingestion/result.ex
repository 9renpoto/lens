defmodule Lens.Ingestion.Result do
  @typedoc "The terminal state of one feed ingestion attempt."
  @type outcome :: :success | :not_modified | :failure

  @typedoc "An entry that could not be persisted while other entries succeeded."
  @type invalid_entry :: %{required(:index) => non_neg_integer(), required(:error) => term()}

  @type t :: %__MODULE__{
          outcome: outcome(),
          status: pos_integer() | nil,
          valid_entries: [map()] | nil,
          invalid_entries: [invalid_entry()] | nil,
          error: String.t() | nil
        }

  @enforce_keys [:outcome]
  defstruct [:outcome, :status, :valid_entries, :invalid_entries, :error]
end
