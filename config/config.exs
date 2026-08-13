import Config

# The component roster the composer validates and composes
# (conventions §4). Grows one entry per system as they land.
config :catapult, :components, [Catapult.Foundation]

config :catapult, ecto_repos: [Catapult.Repo]

config :catapult, Oban,
  repo: Catapult.Repo,
  queues: [],
  plugins: []

config :catapult, serve_health: false

import_config "#{config_env()}.exs"
