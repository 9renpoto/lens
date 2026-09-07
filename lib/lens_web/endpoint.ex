defmodule LensWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :lens

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason)
  plug(LensWeb.Router)
end
