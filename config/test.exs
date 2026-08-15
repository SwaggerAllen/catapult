import Config

config :catapult, Catapult.Repo,
  username: System.get_env("PGUSER", "catapult"),
  password: System.get_env("PGPASSWORD", "catapult"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "catapult_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Oban in manual testing mode: no queues run; jobs assert via
# Oban.Testing (conventions §9 — deterministic, no timing).
config :catapult, Oban, repo: Catapult.Repo, testing: :manual

config :catapult, serve_health: false

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
