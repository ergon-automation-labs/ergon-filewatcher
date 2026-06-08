import Config

# Logger with correlation_id support
config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: {BotArmyRuntime.LoggerFormatter, []},
  metadata: [:correlation_id]

config :bot_army_filewatcher,
  git_status_threshold: String.to_integer(System.get_env("FILEWATCHER_GIT_THRESHOLD", "10")),
  watch_interval_ms: String.to_integer(System.get_env("FILEWATCHER_WATCH_INTERVAL", "1000")),
  watched_dirs:
    String.split(System.get_env("FILEWATCHER_WATCHED_DIRS", "") || "", ",")
    |> Enum.filter(&(&1 != ""))

