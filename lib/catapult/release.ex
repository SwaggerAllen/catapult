defmodule Catapult.Release do
  @moduledoc """
  Release tasks, run via `bin/catapult eval` — no Mix inside a release.

  `migrate/0` is the deploy's PRE_DEPLOY job (`.do/app.yaml`): runs the
  infrastructure migrations and every per-store path that has landed
  (v5 §2.4). `migrations_infra` is foundation's — EventStore's schema
  and Oban's tables; `migrations` is Ecto's default path, where a
  store's own domain tables go, engine's `engine_*` being the first
  (`systems/engine.md`). Order is the list's: infra first, because a
  store's tables may reference what it sets up and nothing in it
  references a store's.
  """

  @app :catapult
  @migration_paths ["migrations_infra", "migrations"]

  # A migrator needs two connections, not the pool a serving node
  # sizes for itself. Without this the PRE_DEPLOY job opens
  # `FOUNDATION_POOL_SIZE` of them while the instance being replaced
  # still holds its own — which is how the job comes to be the thing
  # that exhausts the database it is migrating. The reference
  # instance's own limit and the budget it implies are SETUP.md §2's,
  # recorded once (`docs/non-goals.md`).
  @migrator_pool_size 2

  def migrate do
    Application.load(@app)
    # The app is loaded, not started, so nothing has read configuration
    # yet — and the Repo this is about to start needs it. Same call, same
    # report as a real boot (Catapult.Boot).
    Catapult.Boot.load!()

    for rel <- @migration_paths do
      path = Application.app_dir(@app, Path.join("priv/repo", rel))

      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          Catapult.Repo,
          &Ecto.Migrator.run(&1, path, :up, all: true),
          pool_size: @migrator_pool_size
        )
    end

    :ok
  end
end
