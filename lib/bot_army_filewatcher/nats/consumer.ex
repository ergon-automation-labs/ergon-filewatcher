defmodule BotArmyFileWatcher.NATS.Consumer do
  @moduledoc """
  NATS message consumer for Filewatcher Bot.

  Filewatcher is primarily a watcher (publishes signals),
  not a subscriber, but this module handles any request/reply
  for file status queries.
  """

  use GenServer
  require Logger

  alias BotArmyRuntime.NATS.Reply

  @version Mix.Project.config()[:version]
  @reconnect_delay_ms 5000

  # Register subjects with their metadata for runtime discovery
  @subjects [
    %{
      subject: "filewatcher.status.query",
      type: :request_reply,
      description: "Query current filewatcher status"
    },
    %{
      subject: "filewatcher.git_status.query",
      type: :request_reply,
      description: "Query git status for a directory"
    },
    %{
      subject: "context.state.desired",
      type: :subscribe,
      description: "Subscribe to context state changes (directory changes)"
    },
    %{
      subject: "context.state.query",
      type: :request_reply,
      description: "Request/reply for filewatcher context queries"
    }
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("[Filewatcher] Starting NATS consumer")

    state = %{
      subscriptions: [],
      conn: nil,
      opts: opts
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5000) do
      {:ok, conn} ->
        Logger.info("[Filewatcher] Connected to NATS")

        # Register subjects for runtime discovery
        BotArmyRuntime.Registry.register("filewatcher", @subjects, @version)

        {:noreply, %{state | conn: conn}}

      {:error, _reason} ->
        Logger.warning("[Filewatcher] NATS connection not ready, will retry")
        Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:connect_retry, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[Filewatcher] Disconnected from NATS")
    {:noreply, %{state | conn: nil}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("[Filewatcher] Reconnected to NATS")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      Logger.debug("[Filewatcher] Received NATS message on subject: #{msg.topic}")

      case msg.topic do
        "context.state.desired" ->
          handle_context_desired(msg, state)

        "context.state.query" ->
          handle_context_query(msg, state)

        _ ->
          if msg.reply_to do
            handle_request(msg, state)
          end
      end
    end)

    {:noreply, state}
  end

  # Request handlers

  defp handle_request(msg, state) do
    case msg.topic do
      "filewatcher.status.query" ->
        response = %{
          "ok" => true,
          "schema_version" => "1.0",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "status" => %{
            "watching" => true,
            "watch_interval_ms" => 1000
          }
        }

        BotArmyRuntime.NATS.Reply.ok(response)
        send_response(state, msg.reply_to, response)

      "filewatcher.git_status.query" ->
        # Parse request for directory
        with {:ok, payload} <- Jason.decode(msg.body),
             directory <- Map.get(payload, "directory", System.cwd!()) do
          case get_git_status(directory) do
            {:ok, status} ->
              response = %{
                "ok" => true,
                "schema_version" => "1.0",
                "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
                "directory" => directory,
                "status" => status
              }

              BotArmyRuntime.NATS.Reply.ok(response)
              send_response(state, msg.reply_to, response)

            {:error, reason} ->
              response = %{
                "ok" => false,
                "schema_version" => "1.0",
                "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
                "error" => inspect(reason)
              }

              BotArmyRuntime.NATS.Reply.error(inspect(reason), :git_status_error)
              send_response(state, msg.reply_to, response)
          end
        else
          _ ->
            response = %{
              "ok" => false,
              "schema_version" => "1.0",
              "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
              "error" => "Invalid request payload"
            }

            BotArmyRuntime.NATS.Reply.error("Invalid request payload", :validation_error)
            send_response(state, msg.reply_to, response)
        end

      _ ->
        Logger.debug("[Filewatcher] Unknown request subject: #{msg.topic}")
    end
  end

  defp get_git_status(dir) do
    cmd = "cd #{shell_escape(dir)} && git status --porcelain 2>/dev/null"

    case System.cmd("bash", ["-c", cmd], stderr: :merge) do
      {output, 0} ->
        lines = String.split(String.trim(output), "\n")
        lines = Enum.filter(lines, &(&1 != ""))

        status = %{
          untracked: Enum.count(lines, &String.starts_with?(&1, "??")),
          staged: Enum.count(lines, &String.match?(&1, ~r/^[AMDR]/)),
          unstaged: Enum.count(lines, &String.match?(&1, ~r/^.[AMDR]/)),
          total: Enum.count(lines),
          lines: lines
        }

        {:ok, status}

      {_, _} ->
        # Check if it's a git repo
        if File.exists?(Path.join(dir, ".git")) do
          {:error, "git command failed"}
        else
          {:error, "not_a_git_repo"}
        end
    end
  end

  defp shell_escape(path) do
    String.replace(path, "'", "'\\''")
  end

  defp send_response(state, reply_to, response) do
    if state.conn do
      Gnat.pub(state.conn, reply_to, Jason.encode!(response))
    end
  end

  # Context handlers

  defp handle_context_desired(msg, state) do
    # Extract the desired context state
    case Jason.decode(msg.body) do
      {:ok, payload} ->
        mode = Map.get(payload, "mode")
        path = Map.get(payload, "path")

        if mode == "context_change" and path do
          # Get git status for the new directory
          case get_git_status(path) do
            {:ok, status} ->
              # Check if there are changes worth noting
              total = status.untracked + status.staged + status.unstaged

              if total > 0 do
                # Publish context update with file status
                context_update = %{
                  "event" => "context.signal.filewatcher",
                  "event_id" => UUID.uuid4(),
                  "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
                  "source" => "bot_army_filewatcher",
                  "signal" => %{
                    "type" => "git_changes",
                    "path" => path,
                    "status" => status,
                    "confidence" => "suggested"
                  }
                }

                BotArmyRuntime.NATS.Publisher.publish(
                  "context.signal.filewatcher",
                  context_update
                )

                # Send status to ghostty via reply_to if available
                if msg.reply_to do
                  response = %{
                    "ok" => true,
                    "schema_version" => "1.0",
                    "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
                    "has_updates" => total > 0,
                    "updates" => %{
                      "untracked" => status.untracked,
                      "staged" => status.staged,
                      "unstaged" => status.unstaged,
                      "suggestion" =>
                        if(status.staged + status.unstaged > 0,
                          do: "Run tests?",
                          else: "Repo has untracked files"
                        )
                    }
                  }

                  send_response(state, msg.reply_to, response)
                end
              end

            {:error, _reason} ->
              # Not a git repo or git command failed - just pass through
              nil
          end
        end

      _ ->
        Logger.debug("[Filewatcher] Invalid context.state.desired payload")
    end

    {:noreply, state}
  end

  defp handle_context_query(msg, state) do
    # Handle queries for filewatcher context
    reply_to = Map.get(msg, :reply_to)

    if reply_to do
      # Get current git status for current directory
      case get_git_status(System.cwd!()) do
        {:ok, status} ->
          response = %{
            "ok" => true,
            "schema_version" => "1.0",
            "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
            "has_changes" => status.total > 0,
            "git_status" => status,
            "suggestion" =>
              if(status.staged + status.unstaged > 0, do: "Run tests?", else: "All clean")
          }

          send_response(state, reply_to, response)

        {:error, reason} ->
          response = %{
            "ok" => false,
            "schema_version" => "1.0",
            "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
            "error" => inspect(reason)
          }

          send_response(state, reply_to, response)
      end
    end

    {:noreply, state}
  end
end
