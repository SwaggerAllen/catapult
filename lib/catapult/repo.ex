defmodule Catapult.Repo do
  @moduledoc """
  The one Repo (conventions §6): stores own schemas and queries, never
  connections. Owned by the foundation.

  Its connection settings are *assembled* from the config layer, never
  re-declared there (systems/foundation.md). Ecto reads application env
  by its own contract and will keep doing it; `init/2` is the seam where
  the layer feeds it, so `DATABASE_URL` has exactly one reader in the
  tree. The rejected shape is the obvious one — leave the variable in
  `runtime.exs` because Ecto wants app env anyway — and it is rejected
  because it keeps a second reader of the environment alive, which is
  precisely the thing being removed.
  """
  use Ecto.Repo, otp_app: :catapult, adapter: Ecto.Adapters.Postgres

  alias Catapult.Config

  @impl Ecto.Repo
  def init(_context, config) do
    # Mix's ecto tasks call this after `app.config` and the release
    # migrator under `eval`, both without starting the application, so
    # the boot's load may not have happened. It is idempotent
    # (Catapult.Boot).
    Catapult.Boot.load!()

    {:ok,
     config
     |> Keyword.merge(Config.fetch!(:foundation, :database_url))
     |> Keyword.put(:pool_size, Config.fetch!(:foundation, :pool_size))}
  end
end
