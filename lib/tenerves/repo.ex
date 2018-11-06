defmodule TeNerves.Repo do
  use Ecto.Repo,
    otp_app: :tenerves,
    adapter: Ecto.Adapters.Postgres
end
