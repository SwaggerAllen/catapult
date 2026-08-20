import Config

# The test database's connection parameters are the harness a sandboxed
# suite needs, not any component's behaviour, so they stay on the build
# side — but in `DATABASE_URL` shape, because that is the one
# declaration `Repo.init/2` merges in every environment
# (systems/foundation.md). Built here from the same PG* variables CI
# provides, then seeded into the static source: the suite still reaches
# its database from the config file, and no test reads the environment
# through the config layer (conventions §9).
database_url =
  "ecto://#{System.get_env("PGUSER", "catapult")}:" <>
    "#{System.get_env("PGPASSWORD", "catapult")}@" <>
    "#{System.get_env("PGHOST", "localhost")}/catapult_test"

config :catapult,
       :config_source,
       {Catapult.Config.Static, %{"DATABASE_URL" => database_url}}

# The sandbox pool is genuinely a harness switch and not a connection
# parameter: it selects what this build starts, which is the line
# `config/*.exs` keeps.
config :catapult, Catapult.Repo, pool: Ecto.Adapters.SQL.Sandbox

# Oban in manual testing mode: no queues run; jobs assert via
# Oban.Testing (conventions §9 — deterministic, no timing).
config :catapult, Oban, repo: Catapult.Repo, testing: :manual

config :catapult, serve_health: false

# The in-memory adapter (v5 §2.4's env-switched half): the default
# suite runs the domain offline, with no event store schema to reset
# between async tests. One test (`event_store_test.exs`) starts a
# second, dynamically-named application instance against the real
# Postgres-backed adapter to prove the migration and the adapter wiring
# genuinely work — that test opts itself out of the sandbox rather than
# every other engine test paying for it.
config :catapult, Catapult.Engine.Application,
  event_store: [adapter: Commanded.EventStore.Adapters.InMemory]

# The reference instance's public base URL: the `:live` suite's one
# target (systems/foundation.md). Test config rather than config.exs on
# purpose — prod code must not be able to read the app's own public URL,
# because the first use anyone finds for it is building links out of it,
# and the instance would then be in the tree twice again. Overridable so
# the suite can be aimed at another deployment without a commit.
config :catapult,
       :live_base_url,
       System.get_env("CATAPULT_LIVE_BASE_URL", "https://catapult-ezten.ondigitalocean.app")

config :logger, level: :warning
