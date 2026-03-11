defmodule BravoCredit.Repo do
  use Ecto.Repo,
    otp_app: :bravo_credit,
    adapter: Ecto.Adapters.Postgres
end
