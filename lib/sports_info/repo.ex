defmodule SportsInfo.Repo do
  use Ecto.Repo,
    otp_app: :sports_info,
    adapter: Ecto.Adapters.MyXQL
end
