defmodule LensWeb.DashboardController do
  use LensWeb, :controller

  import Plug.Conn, only: [put_resp_content_type: 2, send_resp: 3]

  alias Lens.Content

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, dashboard_html(Content.dashboard_metrics()))
  end

  defp dashboard_html(metrics) do
    """
    <!doctype html>
    <html lang="en" data-theme="dark">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css">
        <title>Lens service overview</title>
      </head>
      <body>
        <main class="container">
          <nav>
            <ul><li><strong>Lens operations</strong></li></ul>
            <ul><li><small>Refresh this page for current values</small></li></ul>
          </nav>
          <header>
            <hgroup>
              <h1>Service overview</h1>
              <p>Service-wide ingestion metrics</p>
            </hgroup>
          </header>
          <section class="grid" aria-label="Service metrics">
            #{metric_card("Sources", metrics.source_count, "#{metrics.enabled_source_count} active · #{metrics.disabled_source_count} disabled")}
            #{metric_card("Documents", metrics.document_count, "Canonical content stored")}
            #{metric_card("Observations", metrics.observation_count, "Successful captures")}
            #{metric_card("Needs attention", metrics.attention_source_count, "Sources with an ingestion error")}
            #{metric_card("Latest observation", format_datetime(metrics.latest_observation_at), "Most recent successful capture")}
          </section>
          #{attention_panel(metrics.attention_sources)}
        </main>
      </body>
    </html>
    """
  end

  defp metric_card(label, value, hint) do
    """
    <article>
      <header>#{escape(label)}</header>
      <h2>#{escape(value)}</h2>
      <footer><small>#{escape(hint)}</small></footer>
    </article>
    """
  end

  defp attention_panel([]) do
    """
    <article aria-labelledby="attention-heading">
      <header><h2 id="attention-heading">Source health</h2></header>
      <p>No sources need attention.</p>
    </article>
    """
  end

  defp attention_panel(sources) do
    items =
      Enum.map_join(sources, "", fn source ->
        label = source.title || source.endpoint_url
        detail = source.last_error || "#{source.failure_count} consecutive failed fetches"

        """
        <li><strong>#{escape(label)}</strong><br><small>#{escape(detail)} · #{source.failure_count} failures</small></li>
        """
      end)

    """
    <article aria-labelledby="attention-heading">
      <header><h2 id="attention-heading">Source health</h2></header>
      <p>Follow up on failed ingestion.</p>
      <ul>#{items}</ul>
    </article>
    """
  end

  defp format_datetime(nil), do: "No observations yet"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
