defmodule LensWeb.DashboardControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest

  alias Lens.Content

  @endpoint LensWeb.Endpoint

  test "renders a mobile-friendly service metrics dashboard" do
    {:ok, healthy_source} =
      Content.create_source(%{
        source_type: "rss",
        endpoint_url: "https://feeds.example.com/healthy.xml",
        poll_interval_seconds: 300,
        title: "Healthy feed"
      })

    {:ok, _attention_source} =
      Content.create_source(%{
        source_type: "rss",
        endpoint_url: "https://feeds.example.com/attention.xml",
        poll_interval_seconds: 300,
        enabled: false,
        failure_count: 2,
        last_error: "Connection timed out"
      })

    {:ok, _} =
      Content.observe_document(healthy_source, %{
        canonical_url: "https://example.com/articles/dashboard",
        title: "Dashboard article",
        content: "Content for the dashboard"
      })

    conn = get(build_conn(), "/dashboard")

    body = html_response(conn, 200)

    assert body =~ "Service overview"
    assert body =~ "2"
    assert body =~ "1"
    assert body =~ "Documents"
    assert body =~ "Observations"
    assert body =~ "Needs attention"
    assert body =~ "Connection timed out"
    assert body =~ "viewport"
    assert body =~ "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"
    refute body =~ "<style>"
  end
end
