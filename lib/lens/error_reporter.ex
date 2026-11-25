defmodule Lens.ErrorReporter do
  @moduledoc "Reports ingestion failures without disclosing source material or target context."

  @stage_atoms ~w(discovery acquisition association extraction indexing publication)a
  @stages Enum.map(@stage_atoms, &Atom.to_string/1)
  @publication_reason_atoms ~w(issuer_unconfigured issuer_unverified issuer_mismatch)a
  @publication_reasons Enum.map(@publication_reason_atoms, &Atom.to_string/1)
  @failure_kinds ~w(error exception)

  @spec report(atom(), term()) :: :ok
  def report(stage, failure) when stage in @stage_atoms do
    kind = if is_exception(failure), do: "exception", else: "error"

    extra = %{"stage" => Atom.to_string(stage), "failure_kind" => kind}

    extra =
      if stage == :publication and failure in @publication_reason_atoms,
        do: Map.put(extra, "reason", Atom.to_string(failure)),
        else: extra

    Sentry.Event.create_event(
      message: "Earnings ingestion failed",
      event_source: :lens_ingestion,
      extra: extra
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
        extra: %{"stage" => stage, "failure_kind" => kind} = extra
      })
      when stage in @stages and kind in @failure_kinds do
    reason = extra["reason"]
    details = %{"stage" => stage, "failure_kind" => kind}

    details =
      if stage == "publication" and reason in @publication_reasons,
        do: Map.put(details, "reason", reason),
        else: details

    %Sentry.Event{
      event_id: Sentry.UUID.uuid4_hex(),
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      message: %Sentry.Interfaces.Message{formatted: "Earnings ingestion failed"},
      level: :error,
      source: :lens_ingestion,
      environment: nil,
      request: nil,
      user: nil,
      extra: details,
      fingerprint: ["earnings_ingestion", stage, kind]
    }
  end

  def before_send(_event), do: false
end
