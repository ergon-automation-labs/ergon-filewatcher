defmodule BotArmyFileWatcher.Repo do
  use Ecto.Repo,
    otp_app: :bot_army_filewatcher,
    adapter: Ecto.Adapters.Postgres
end
