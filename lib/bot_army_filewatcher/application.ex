defmodule BotArmyFileWatcher.Application do
  @moduledoc """
  Filewatcher bot application supervisor.

  Monitors filesystem changes and git status, publishing signals
  to the context broker and triggering test suggestions when
  relevant files change.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      BotArmyFileWatcher.PulsePublisher,
      BotArmyFileWatcher.Watcher
    ]

    opts = [strategy: :one_for_one, name: __MODULE__.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
