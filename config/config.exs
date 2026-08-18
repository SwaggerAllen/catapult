import Config

# The component roster the composer validates and composes
# (conventions §4). Grows one entry per system as they land.
config :catapult, :components, [Catapult.Foundation, Catapult.Dsl]

config :catapult, ecto_repos: [Catapult.Repo]

config :catapult, Oban,
  repo: Catapult.Repo,
  queues: [],
  plugins: []

config :catapult, serve_health: false

# The export macro's Logger metadata floor (ORC-21,
# `Catapult.Component.API`): `component:` at every boundary entry and
# `trace_id:` at the root of each trace. Declared here because Logger
# drops metadata keys a backend was never told about — the floor is set
# in the substrate and *kept* in the composing application's config,
# which is the same split as every other value.
config :logger, :default_formatter, metadata: [:component, :trace_id, :request_id]

import_config "#{config_env()}.exs"
