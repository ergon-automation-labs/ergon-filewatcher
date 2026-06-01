defmodule BotArmyFileWatcher.Schemas.GitStatus do
  @moduledoc """
  Schema for storing git status snapshots.
  """

  use Ecto.Schema
  alias BotArmyFileWatcher.Repo

  @primary_key false
  schema "git_status_snapshots" do
    field :directory, :string, primary_key: true
    field :untracked, :integer, default: 0
    field :staged, :integer, default: 0
    field :unstaged, :integer, default: 0
    field :total, :integer, default: 0
    field :detected_at, :utc_datetime
  end
end
