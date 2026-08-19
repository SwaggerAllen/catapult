defmodule Catapult.Boot do
  @moduledoc """
  What every entry point needs before anything else runs: the component
  roster, the config source, and the one call that validates the
  registries and loads every declared value (systems/foundation.md).

  Root glue in v5 §2.7's sense — composed from declarations, never
  hand-maintained. It exists as its own module rather than as functions
  on `Catapult.Application` because the application is not the only
  entry point: `Catapult.Release.migrate/0` runs under `bin/catapult
  eval` with the app loaded but not started, and mix's ecto tasks call
  `Catapult.Repo.init/2` after `app.config` and before anything starts a
  supervision tree. Both need configuration and neither boots the
  application. Hanging `load!/0` off `Catapult.Application` instead
  would put `Catapult.Repo` → `Catapult.Application` → `Catapult.Foundation`
  → `Catapult.Repo` in the module graph, and cycles are a hard gate
  (conventions §2).

  ## The source is chosen at compile time, because it is the bottom turtle

  v5 §2.12 has every external's real-vs-fake selection ride config;
  config's own source therefore cannot, since reading an environment
  variable to decide whether to read environment variables is the circle
  it looks like. The selection carries the source's own settings with it
  — `{Catapult.Config.Static, %{"DATABASE_URL" => "..."}}` — which is
  the one bounded exception to "one reader of the environment", and it
  is a source's bootstrap rather than any component's value.

  Dev and test select the static fake, seeded in `config/dev.exs` and
  `config/test.exs`; every real build gets `Catapult.Config.Env`. That
  is also what settles `.env` files: a dotenv file exists to feed
  environment variables to a process that reads the environment, and dev
  does not (systems/substrate.md).
  """

  alias Catapult.Component.Composer
  alias Catapult.Config

  @components Application.compile_env!(:catapult, :components)
  @config_source Application.compile_env(:catapult, :config_source, {Config.Env, []})

  @doc "The composed component roster, as declared in `config/config.exs`."
  @spec components() :: [module()]
  def components, do: @components

  @doc """
  Validates the registry set and loads every declared config value.

  Two reports in one call, in the only order that works: structure first
  (collisions, malformed declarations — a problem with no environment in
  it), then values. Both enumerate rather than stopping at the first
  problem, because N restart cycles to discover N problems is hostile to
  whoever is holding the deploy.

  Idempotent, so an entry point may call it without knowing whether
  another already did.
  """
  @spec load!() :: :ok
  def load! do
    Composer.validate!(@components)
    Config.load!(@components, @config_source)
  end
end
