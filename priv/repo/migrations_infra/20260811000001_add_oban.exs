defmodule Catapult.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Infrastructure persistence (conventions §6): Oban owns its tables
  # under its reserved prefix; app code reaches them only through the
  # Oban API. Migrations ship here, in the foundation.
  #
  # v14 matches oban 2.23 (the series bump). Edited in place rather
  # than appended: no database outside throwaway CI has ever run this
  # migration — append-only discipline starts at the first deploy.
  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 1)
end
