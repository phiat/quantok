defmodule Quantok.Repo do
  use Ecto.Repo,
    otp_app: :quantok,
    adapter: Application.compile_env(:quantok, :ecto_adapter, Ecto.Adapters.SQLite3)
end
