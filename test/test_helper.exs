# Scheduler callbacks are exercised explicitly in scheduler tests. Its application
# poller must not access SQL Sandbox connections without a test owner.
:ok = :sys.suspend(Lens.Ingestion.Scheduler)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(Lens.Repo, :manual)
