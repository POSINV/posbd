defmodule Posbd.Repo do
  use Ecto.Repo,
    otp_app: :posbd,
    adapter: Ecto.Adapters.Postgres
end
