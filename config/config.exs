import Config

# The component roster the composer validates and composes
# (conventions §4). Grows one entry per system as they land.
config :catapult, :components, [
  Catapult.Foundation,
  Catapult.Dsl,
  Catapult.Engine,
  Catapult.Delivery,
  Catapult.Generation
]

config :catapult, ecto_repos: [Catapult.Repo]

config :catapult, Oban,
  repo: Catapult.Repo,
  # The dispatch-concurrency cap (v5 §7.12.1's bindings `tunable`) as a
  # config constant for now: no plane-state/bindings storage exists
  # anywhere in this codebase yet to hold a true per-instance tunable
  # (`systems/generation.md`'s own aspiration), and building that
  # storage is its own ticket, not this one's. Same treatment
  # `ENGINE_SWEEPER_INTERVAL_MS` already gets for the identical reason
  # (`Catapult.Engine`'s own `config/0`) — precedent, not a new gap.
  queues: [generation_dispatch: 5],
  plugins: []

# The seam `Catapult.Delivery.Dispatch` calls into once a result-report
# is authenticated and correlated (`Catapult.Delivery.ResultHandler`) —
# an atom read at call time via `Application.get_env/2`, never a
# literal alias, so delivery names no dependency on generation in
# source despite generation depending on delivery for dispatch
# (`Catapult.Delivery.ResultHandler`'s own moduledoc).
config :catapult, :generation_result_handler, Catapult.Generation.CommitPath

# `pubsub`/`registry` are `:local` in every environment Catapult itself
# runs (topology starts `single`, systems/foundation.md) — a build-shape
# constant, not an instance tunable. The event store *adapter* differs
# per environment (env-switched, v5 §2.4) and is declared per env.exs
# below, same split as `serve_health`/Oban's `testing: :manual`.
config :catapult, Catapult.Engine.Application, pubsub: :local, registry: :local

config :catapult, serve_health: false

# The export macro's Logger metadata floor (ORC-21,
# `Catapult.Component.API`): `component:` at every boundary entry and
# `trace_id:` at the root of each trace. Declared here because Logger
# drops metadata keys a backend was never told about — the floor is set
# in the substrate and *kept* in the composing application's config,
# which is the same split as every other value.
config :logger, :default_formatter, metadata: [:component, :trace_id, :request_id]

import_config "#{config_env()}.exs"
