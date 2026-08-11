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

config :logger, level: :warning
