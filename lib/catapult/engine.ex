defmodule Catapult.Engine do
  @moduledoc """
  The reactive core (`systems/engine.md`): the Commanded application,
  per-project aggregates and the event log, the reducer generic over
  bundle semantics, and the universal projections. The first consumer
  of the ES store family (v5 §2.4) — its purity floors and `events/0`
  registry are proven here before any target app uses them.
  """

  use Catapult.Component, slug: :engine

  alias Catapult.Engine.Events

  @impl Catapult.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-only"]

  @impl Catapult.Component
  def config do
    [
      # The event store runs its own Postgrex pool, separate from
      # `Catapult.Repo`'s, against the same database (its `init/1`).
      # Declared rather than left to the library's default because the
      # connection budget is shared and finite (SETUP.md §2 records
      # the reference instance's limit and the sizing that follows
      # from it) and an inherited default is a number nobody chose
      # competing for it. An instance
      # tunable, so it comes from the environment
      # (`systems/foundation.md`'s build-shape/instance-shape line),
      # with the same default `FOUNDATION_POOL_SIZE` carries — and
      # that default is small on purpose: the only deployment this
      # code has is the one SETUP.md §2 describes, so a default that
      # needs an environment variable set before a deploy can succeed
      # is a default that has failed at the one job it has.
      {:event_store_pool_size, "ENGINE_EVENT_STORE_POOL_SIZE", cast: :integer, default: "2"},
      # Where the reactive scheduler (`Catapult.Engine.Scheduler`, via
      # the projector's fast path and `Catapult.Engine.Sweeper`) loads
      # a `Catapult.Dsl.Chain` from — a directory containing
      # `catapult.yaml` and `bundles/`. Defaults to the reference
      # deployment's own layout (both live at this repo's root, the
      # same single project `topology: single` already assumes); a
      # real per-project bundle root is a not-yet-built concern this
      # ticket does not invent (`systems/engine.md`).
      {:bundles_root, "ENGINE_BUNDLES_ROOT", cast: :string, default: "."},
      # The sweeper's cadence (v5 §7.10's bindings surface, `tunable`
      # per `systems/engine.md`): enough headroom that a burst of
      # events doesn't turn the convergence floor into a second fast
      # path, short enough that a lost PubSub message is invisible in
      # practice.
      {:sweeper_interval_ms, "ENGINE_SWEEPER_INTERVAL_MS", cast: :integer, default: "30000"}
    ]
  end

  @impl Catapult.Component
  def events, do: Events.registry()

  @impl Catapult.Component
  def pubsub_topics, do: [:ready_scopes]

  @impl Catapult.Component
  def policies do
    policy = "v5 §2.4: no clocks, randomness, or generated ids in fold/projection code"

    for scope <- [
          "lib/catapult/engine/reducer.ex",
          "lib/catapult/engine/aggregate.ex",
          "lib/catapult/engine/events/review_written_v1.ex",
          "lib/catapult/engine/projections/**/*.ex"
        ] do
      {Catapult.Engine.Policies.PurityFloor, scope, policy: policy}
    end
  end

  @impl Catapult.Component
  def processes do
    [
      {:engine_projector, :singleton},
      # `:singleton`, the same kind `engine_projector` already uses —
      # not `:local`: a rolling deploy's brief two-instance overlap
      # must run one sweeper cluster-wide, not two, against the same
      # finite connection budget the sweeper's own moduledoc prices
      # (`systems/engine.md`).
      {:engine_sweeper, :singleton}
    ]
  end

  @impl Catapult.Component
  def children do
    # `Catapult.Engine.EventStore` is deliberately absent, in every
    # environment: the Commanded adapter starts it. Its `child_spec/2`
    # pops `event_store:` out of the configured keyword list and
    # returns `[{event_store, config}]`, so the module is already a
    # child of this application's own supervision tree — under its own
    # module name, since nothing passes a `name:` to disambiguate.
    # Listing it here as well started it twice under one registered
    # name: the composer's start won, the adapter's returned
    # `{:error, {:already_started, _}}`, and the Commanded supervisor
    # took the boot down with it. Only the persistent adapter reaches
    # that path — test runs `Commanded.EventStore.Adapters.InMemory`,
    # which has no such child — so the whole suite passed while every
    # deploy crash-looped (`event_store.ex`'s own moduledoc had it
    # right; this function disagreed with it).
    [Catapult.Engine.Application, Catapult.Engine.Projector, Catapult.Engine.Sweeper]
  end
end
