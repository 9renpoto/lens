defmodule Lens.ErrorReporterTest do
  use ExUnit.Case, async: true

  alias Lens.ErrorReporter

  defmodule Transport do
    @behaviour Sentry.HTTPClient
    @impl true
    def post(_url, _headers, body) do
      send(self(), {:envelope, IO.iodata_to_binary(body)})
      {:ok, 200, [], "{}"}
    end
  end

  defmodule BrokenTransport do
    @behaviour Sentry.HTTPClient
    @impl true
    def post(_, _, _), do: raise("synthetic transport failure")
  end

  setup do
    Sentry.Test.Config.put(
      dsn: "https://public@example.test/1",
      send_result: :sync,
      dedup_events: false,
      client: Transport
    )

    :ok
  end

  test "reports expected failures and exceptions through the SDK without raw details" do
    Sentry.Context.set_extra_context(%{body: "synthetic-private-body"})
    Sentry.Context.set_user_context(%{id: "synthetic-target"})
    Sentry.Context.add_breadcrumb(%{message: "https://private.example.test/source"})

    for error <- [{:error, "synthetic-private-body"}, %RuntimeError{message: "synthetic-target"}] do
      assert :ok = ErrorReporter.report(:extraction, error)
      assert_receive {:envelope, body}
      refute body =~ "synthetic-private-body"
      refute body =~ "synthetic-target"
      refute body =~ "private.example.test"
      assert body =~ "extraction"
      assert body =~ "Earnings ingestion failed"
    end
  end

  test "before_send rebuilds allowlisted events and drops unrecognized events" do
    event = Sentry.Event.create_event(message: "synthetic-secret")
    assert ErrorReporter.before_send(event) == false

    event = %{
      event
      | source: :lens_ingestion,
        extra: %{
          "stage" => "discovery",
          "failure_kind" => "exception",
          "token" => "synthetic-secret"
        },
        server_name: "private.example.test",
        attachments: [%Sentry.Attachment{filename: "synthetic-secret", data: "synthetic-secret"}],
        original_exception: %RuntimeError{message: "synthetic-secret"},
        release: "synthetic-secret"
    }

    clean = ErrorReporter.before_send(event)
    refute inspect(clean) =~ "synthetic-secret"
    refute inspect(clean) =~ "private.example.test"
    assert clean.attachments == []
    assert clean.exception == []
    assert clean.breadcrumbs == []
    assert clean.extra == %{"stage" => "discovery", "failure_kind" => "exception"}
    assert clean.server_name == nil
    assert clean.modules == %{}
  end

  test "reporting failures never escape into the ingestion caller" do
    Sentry.Test.Config.put(client: BrokenTransport)
    assert :ok = ErrorReporter.report(:indexing, {:error, :unavailable})
  end

  test "absent DSN disables delivery and invalid stages never become payload data" do
    Sentry.Test.Config.put(dsn: nil)
    assert :ok = ErrorReporter.report(:acquisition, {:error, :timeout})
    refute_receive {:envelope, _}
    Sentry.Test.Config.put(dsn: "https://public@example.test/1")
    assert :ok = ErrorReporter.report("synthetic-secret", :failure)
    refute_receive {:envelope, _}
  end
end
