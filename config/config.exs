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
  # Claimed by `Catapult.Generation.oban_queues/0` and
  # `Catapult.Delivery.oban_queues/0` respectively; this list is what
  # actually starts them (`Catapult.Foundation.children/0` reads it
  # directly). `delivery_flag_flip` is deliberately small: a container
  # closes once, and its flip is one idempotent call. `delivery_feature
  # _publish` is concurrency-1 for a related but distinct reason
  # (`Catapult.Delivery.FeaturePublishWorker`'s own moduledoc, ORC-33):
  # serializing it is what keeps two nodes in the same flow, committed
  # close together, from each finding no feature-publication row and
  # each opening a branch and a PR.
  queues: [generation_dispatch: 5, delivery_flag_flip: 1, delivery_feature_publish: 1],
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

# `CatapultWeb.Endpoint`'s build-shape config (ORC-35's dev pass):
# `secret_key_base` and the HTTP port are instance-shape and come from
# `Catapult.Config` instead (`Catapult.Application.endpoint_child/0`),
# per ORC-4's split. `pubsub_server` names the PubSub this same
# supervision tree starts alongside it — LiveView's own transport, not
# `Commanded.PubSub` (`Catapult.Engine.Topics`'s "already configured...
# already started" — a second, App-owned PubSub the web layer needs
# regardless of whether any engine broadcast ever reaches a socket).
config :catapult, CatapultWeb.Endpoint,
  render_errors: [formats: [html: CatapultWeb.ErrorHTML], layout: false],
  pubsub_server: CatapultWeb.PubSub,
  live_view: [signing_salt: "catapult-dashboard-lv"]

# The export macro's Logger metadata floor (ORC-21,
# `Catapult.Component.API`): `component:` at every boundary entry and
# `trace_id:` at the root of each trace. Declared here because Logger
# drops metadata keys a backend was never told about — the floor is set
# in the substrate and *kept* in the composing application's config,
# which is the same split as every other value.
# The `:tailwind` package's own build-shape config (ORC-183,
# `systems/dashboard.md`): a profile name (`catapult`), the source/output
# pair `mix assets.build`/`mix assets.deploy` (mix.exs aliases) invoke
# via `mix tailwind catapult` under the hood, and `cd:` so the standalone
# CLI resolves `assets/css/app.css`'s own relative `@plugin`s
# (`assets/vendor/daisyui.js`, `assets/vendor/daisyui-theme.js`) against
# the project root rather than wherever `mix` happened to be invoked from.
config :tailwind,
  version: "4.3.3",
  catapult: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter, metadata: [:component, :trace_id, :request_id]

import_config "#{config_env()}.exs"
