defmodule BotArmyFileWatcher.PulsePublisher do
  @moduledoc """
  Publishes regular system health and capability snapshots.
  """

  use GenServer
  require Logger

  @health_interval_ms 30_000
  @pulse_interval_ms 30 * 60_000
  @source "bot_army_filewatcher"
  @version Mix.Project.config()[:version]

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    Logger.info("[FileWatcher] Starting pulse publisher")

    state = %{
      health_ref: nil,
      pulse_ref: nil
    }

    {:ok, state, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state) do
    schedule_health()
    schedule_pulse()
    {:noreply, state}
  end

  @impl true
  def handle_info(:publish_health, state) do
    publish_health()
    schedule_health()
    {:noreply, state}
  end

  @impl true
  def handle_info(:publish_pulse, state) do
    publish_pulse()
    schedule_pulse()
    {:noreply, state}
  end

  # Helper functions

  defp schedule_health do
    Process.send_after(self(), :publish_health, @health_interval_ms)
  end

  defp schedule_pulse do
    Process.send_after(self(), :publish_pulse, @pulse_interval_ms)
  end

  defp publish_health do
    payload = %{
      "event" => "system.health",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => @source,
      "source_node" => node() |> Atom.to_string(),
      "schema_version" => "1.0",
      "payload" => %{
        "service" => "filewatcher",
        "status" => "healthy",
        "uptime_seconds" => uptime_seconds(),
        "watched_dirs" => watched_dirs_count(),
        "git_repos_watched" => git_repos_count()
      }
    }

    BotArmyRuntime.NATS.Publisher.publish("system.health", payload)
  end

  defp publish_pulse do
    payload = %{
      "event" => "bot.filewatcher.pulse",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => @source,
      "source_node" => node() |> Atom.to_string(),
      "schema_version" => "1.0",
      "payload" => %{
        "version" => @version,
        "watched_dirs" => watched_dirs_count(),
        "git_repos_watched" => git_repos_count()
      }
    }

    BotArmyRuntime.NATS.Publisher.publish("bot.filewatcher.pulse", payload)
  end

  defp uptime_seconds do
    {ms, _} = :erlang.statistics(:wall_clock)
    div(ms, 1000)
  end

  defp watched_dirs_count do
    # Returns count of directories being watched
    # For now, return a static count - would be populated by watcher
    0
  end

  defp git_repos_count do
    # Returns count of git repos being monitored
    0
  end
end
