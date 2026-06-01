config :bot_army_filewatcher,
  git_status_threshold: String.to_integer(System.get_env("FILEWATCHER_GIT_THRESHOLD", "10")),
  watch_interval_ms: String.to_integer(System.get_env("FILEWATCHER_WATCH_INTERVAL", "1000")),
  watched_dirs: String.split(System.get_env("FILEWATCHER_WATCHED_DIRS", "") || "", ",") |> Enum.filter(&(&1 != ""))
