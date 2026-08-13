defmodule Catapult.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Infrastructure persistence (conventions §6): Oban owns its tables
  # under its reserved prefix; app code reaches them only through the
  # Oban API. Migrations ship here, in the foundation.
  def up, do: Oban.Migration.up(version: 12)
  def down, do: Oban.Migration.down(version: 1)
end
