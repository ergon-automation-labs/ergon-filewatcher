defmodule BotArmyFileWatcher.MixProject do
  use Mix.Project

  def version do
    @version
  end

  def project do
    [
      app: :bot_army_filewatcher,
      version: @version || "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {BotArmyFileWatcher.Application, []}
    ]
  end

  defp deps do
    [
      {:bot_army_runtime, "~> 0.14"},
      {:bot_army_core, "~> 0.3"},
      {:ecto, "~> 3.10"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.16"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:uuid, "~> 0.8"}
    ]
  end

  defp aliases do
    [
      test: ["test --no-start"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
