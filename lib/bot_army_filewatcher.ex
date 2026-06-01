defmodule BotArmyFileWatcher do
  @moduledoc """
  Filewatcher bot - monitors filesystem changes and git status.

  This bot watches for:
  - Directory changes (PWD changes in terminals)
  - File changes in bot source directories
  - Git status (untracked files, staged changes, dirty repos)

  It publishes context updates and test suggestions based on
  detected changes.

  ## NATS Subjects

  **Subscribes:**
  - None (主动 watcher, no inbound messages)

  **Publishes:**
  - `context.signal.filewatcher` - File/directory change signals
  - `context.state.proposed` - Proposed context state changes
  - `events.filewatcher.file_changed` - File change events
  - `events.filewatcher.git_status` - Git status snapshots
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
