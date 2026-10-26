defmodule Lens.ErrorReporter do
  @moduledoc "Reports ingestion failures without disclosing source material or target context."

  @stages ~w(discovery acquisition association extraction indexing)
  @stage_atoms ~w(discovery acquisition association extraction indexing)a
  @failure_kinds ~w(error exception)

  @spec report(atom(), term()) :: :ok
  def report(stage, failure) when stage in @stage_atoms do
    kind = if is_exception(failure), do: "exception", else: "error"

    Sentry.Event.create_event(
      message: "Earnings ingestion failed",
      event_source: :lens_ingestion,
      extra: %{"stage" => Atom.to_string(stage), "failure_kind" => kind}
    )
    |> Sentry.send_event(before_send: {__MODULE__, :before_send})

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  def report(_stage, _failure), do: :ok

  @spec before_send(term()) :: Sentry.Event.t() | false
  def before_send(%Sentry.Event{
        source: :lens_ingestion,
        extra: %{"stage" => stage, "failure_kind" => kind}
      })
      when stage in @stages and kind in @failure_kinds do
    %Sentry.Event{
      event_id: Sentry.UUID.uuid4_hex(),
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      message: %Sentry.Interfaces.Message{formatted: "Earnings ingestion failed"},
      level: :error,
      source: :lens_ingestion,
      environment: nil,
      request: nil,
      user: nil,
      extra: %{"stage" => stage, "failure_kind" => kind},
      fingerprint: ["earnings_ingestion", stage, kind]
    }
  end

  def before_send(_event), do: false
end
