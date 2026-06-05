defmodule BotArmyFileWatcher.Watcher do
  @moduledoc """
  File and directory watcher for Bot Army.

  Monitors:
  - PWD changes in terminal sessions
  - File changes in bot source directories
  - Git status (untracked files, staged changes)

  Publishes signals to context broker for:
  - Context mode changes based on directory
  - Test suggestions when relevant files change
  - Git status warnings when repos are dirty
  """

  use GenServer
  require Logger

  @watch_interval_ms 1000
  @git_status_threshold Application.compile_env(:bot_army_filewatcher, :git_status_threshold, 10)

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("[FileWatcher] Starting watcher")

    # Initial git status check
    check_git_status()

    state = %{
      last_watch: nil
    }

    {:ok, state, {:continue, :watch}}
  end

  @impl true
  def handle_continue(:watch, state) do
    Process.send_after(self(), :watch_loop, 0)
    {:noreply, state}
  end

  @impl true
  def handle_info(:watch_loop, state) do
    # Watch for directory changes (via PWD from shell plugins or tmux)
    watch_directory_changes()

    # Check git status
    check_git_status()

    Process.send_after(self(), :watch_loop, @watch_interval_ms)
    {:noreply, state}
  end

  # Directory watching

  defp watch_directory_changes do
    case File.cwd() do
      {:ok, _cwd} -> :ok
      {:error, reason} -> Logger.warning("[FileWatcher] Failed to get cwd: #{inspect(reason)}")
    end
  end

  # Git status monitoring

  defp check_git_status do
    watched_dirs = get_watched_dirs()

    Enum.each(watched_dirs, &check_directory_status/1)
  end

  defp get_watched_dirs do
    case Application.get_env(:bot_army_filewatcher, :watched_dirs, []) do
      [] ->
        [
          "/Users/abby/code/bots/bot_army_gtd",
          "/Users/abby/code/bots/bot_army_context_broker",
          "/Users/abby/code/bots/bot_army_weather_bot"
        ]

      dirs when is_list(dirs) ->
        dirs
    end
  end

  defp check_directory_status(dir) do
    if File.dir?(dir) do
      case get_git_status(dir) do
        {:ok, status} ->
          handle_git_status(dir, status)

        {:error, reason} ->
          Logger.debug("[FileWatcher] Git status for #{dir}: #{inspect(reason)}")
      end
    end
  end

  defp get_git_status(dir) do
    # Run git status --porcelain to get machine-readable output
    cmd = "cd #{shell_escape(dir)} && git status --porcelain 2>/dev/null || echo 'not_a_git_repo'"
    output = System.cmd("bash", ["-c", cmd], stderr: :merge)

    case output do
      {_, 0} ->
        # Parse output
        lines = String.split(trim_output(output), "\n")

        status = %{
          untracked: Enum.count(lines, &String.starts_with?(&1, "??")),
          staged: Enum.count(lines, &String.match?(&1, ~r/^[AMDR]/)),
          unstaged: Enum.count(lines, &String.match?(&1, ~r/^.[AMDR]/)),
          total: Enum.count(lines)
        }

        {:ok, status}

      {_, _} ->
        {:error, "git command failed"}
    end
  end

  defp trim_output({output, _}) do
    String.trim(output)
  end

  defp shell_escape(path) do
    # Escape path for shell
    String.replace(path, "'", "'\\''")
  end

  defp handle_git_status(dir, status) do
    total = status.untracked + status.staged + status.unstaged

    # Publish git status event
    publish_git_status_event(dir, status)

    # Check for untracked files threshold
    if status.untracked > @git_status_threshold do
      warn_dirty_repo(dir, status)
    end

    # Publish test suggestion if files changed
    if total > 0 do
      maybe_suggest_tests(dir, status)
    end
  end

  defp publish_git_status_event(dir, status) do
    payload = %{
      "event" => "events.filewatcher.git_status",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_filewatcher",
      "source_node" => node() |> Atom.to_string(),
      "schema_version" => "1.0",
      "payload" => %{
        "directory" => dir,
        "status" => status,
        "detected_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    BotArmyRuntime.NATS.Publisher.publish("events.filewatcher.git_status", payload)
  end

  defp warn_dirty_repo(dir, status) do
    Logger.warning([
      "[FileWatcher] DIRTY REPO DETECTED: ",
      dir,
      "\n  Untracked: ",
      Integer.to_string(status.untracked),
      " files\n  Consider cleaning up with: git clean -fd"
    ])

    # Publish warning event
    payload = %{
      "event" => "events.filewatcher.dirty_repo_warning",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_filewatcher",
      "source_node" => node() |> Atom.to_string(),
      "schema_version" => "1.0",
      "payload" => %{
        "directory" => dir,
        "reason" => "too_many_untracked_files",
        "untracked_count" => status.untracked,
        "suggestion" => "Run 'git clean -fd' to remove untracked files"
      }
    }

    BotArmyRuntime.NATS.Publisher.publish("events.filewatcher.dirty_repo_warning", payload)
  end

  defp maybe_suggest_tests(dir, status) do
    # Check if this is a bot directory and suggest tests
    if bot_name = detect_bot_from_path(dir) do
      # Only suggest if there are actual source file changes
      if status.staged > 0 or status.unstaged > 0 do
        publish_test_suggestion(bot_name, status)
      end
    end
  end

  defp publish_test_suggestion(bot_name, status) do
    payload = %{
      "event" => "events.filewatcher.test_suggestion",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_filewatcher",
      "source_node" => node() |> Atom.to_string(),
      "schema_version" => "1.0",
      "payload" => %{
        "bot" => bot_name,
        "changed_files" => status.total,
        "untracked" => status.untracked,
        "suggestion" => "Run tests for #{bot_name}?",
        "command" => "cd ~/code/elixir_bots/bot_army_#{bot_name} && mix test",
        "context" => %{
          "mode" => "development",
          "confidence" => "suggested"
        }
      }
    }

    BotArmyRuntime.NATS.Publisher.publish("events.filewatcher.test_suggestion", payload)
  end
end
