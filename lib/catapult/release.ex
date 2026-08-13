defmodule Catapult.Release do
  @moduledoc """
  Release tasks, run via `bin/catapult eval` — no Mix inside a release.

  `migrate/0` is the deploy's PRE_DEPLOY job (`.do/app.yaml`): runs the
  infrastructure migrations. Per-store migration paths compose into
  @migration_paths as stores land (v5 §2.4); today only the infra path
  exists.
  """

  @app :catapult
  @migration_paths ["migrations_infra"]

  def migrate do
    Application.load(@app)

    for rel <- @migration_paths do
      path = Application.app_dir(@app, Path.join("priv/repo", rel))

      {:ok, _, _} =
        Ecto.Migrator.with_repo(Catapult.Repo, &Ecto.Migrator.run(&1, path, :up, all: true))
    end

    :ok
  end
end
