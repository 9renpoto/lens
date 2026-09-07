defmodule Lens.Repo do
  use Ecto.Repo,
    otp_app: :lens,
    adapter: Ecto.Adapters.Postgres
end
