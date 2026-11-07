defmodule Dripstone.Repo do
  use Ecto.Repo,
    otp_app: :dripstone,
    adapter: Ecto.Adapters.Postgres
end
