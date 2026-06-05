defmodule BotArmyFileWatcher.MixProject do
  use Mix.Project

  @version "0.1.1"

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
      docs: docs(),
      releases: [
        filewatcher_bot: [
          applications: [bot_army_filewatcher: :permanent]
        ]
      ]
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
      {:bot_army_library_runtime,
       git: "git@github.com:ergon-automation-labs/ergon-library-runtime.git", branch: "main"},
      {:bot_army_library_core,
       git: "git@github.com:ergon-automation-labs/ergon-library-core.git", branch: "main"},
      {:ecto, "~> 3.10"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.16"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:elixir_uuid, "~> 1.2"},

      # Development/Test
      {:ex_doc, "~> 0.30", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test]},
      {:excoveralls, "~> 0.17", only: :test},
      {:mox, "~> 1.0", only: :test}
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
