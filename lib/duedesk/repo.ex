defmodule DueDesk.Repo do
  use Ecto.Repo,
    otp_app: :duedesk,
    adapter: Ecto.Adapters.Postgres
end
