defmodule Polticool.Repo do
  use Ecto.Repo,
    otp_app: :polticool,
    adapter: Ecto.Adapters.Postgres
end
