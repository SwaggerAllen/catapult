defmodule Catapult do
  @moduledoc """
  The top-level boundary. One coarse boundary today; per-system
  boundaries (engine, dsl, generation, delivery, ... — see systems/)
  carve out of it as those systems land, per conventions §4. The
  boundary compiler is in the gate set from day one so the carving is
  enforced the moment it starts.

  ## The `deps:` list is the external surface, and it is checked

  External-dependency checking is armed in `mix.exs` (ORC-21,
  systems/foundation.md) for the applications v5 §2.14's adapter rules
  are about, so this list is not documentation: a call into one of them
  from anywhere in the tree is named here or the build fails.

  Those four rules — only `Store` subcomponents on Ecto, only the outbox
  wrapper on Oban's insert surface, only adapters on Req, no model-call
  library in plane code — are each a rule about a *sub-boundary*, so none
  of them can be stated while there is one boundary. They arrive as
  `deps:` lines on the boundaries they constrain, which is what arming
  the checking now buys: a carve-out lands already checked instead of
  retrofitted.

  ## What it does not cover, so the gap is not mistaken for coverage

  Boundary documents that calls to `:elixir`, `:boundary` and pure Erlang
  applications cannot be restrained. So a plane module reaching a model
  provider through `:httpc` compiles clean here, and conventions §11 is a
  compile error for every Elixir client the app list names, and for the
  Erlang ones the plane-owned transport ban at
  `Catapult.Foundation.Policies.ErlangHttp` (`systems/foundation.md`),
  registered through `Catapult.Foundation.policies/0` rather than shipped
  in substrate (`systems/substrate.md`). Naming which half is which is
  the difference between a gate and a belief about a gate.
  """
  use Boundary,
    deps: [
      # An implicit boundary covers a module namespace *within one
      # application*, so `:ecto` and `:ecto_sql` are four entries rather
      # than one. The Store rule that narrows any of them to Store
      # subcomponents is those boundaries' line, not this one's.
      Ecto,
      Ecto.Adapters.Postgres,
      Ecto.Adapters.SQL,
      # `test/support/data_case.ex`'s own sandbox setup — pre-existing
      # (not this ticket's), surfaced the same way `Commanded.EventStore`
      # was above: uncaught until an edit to this file's boundary config
      # invalidated the compile cache that had been hiding it.
      Ecto.Adapters.SQL.Sandbox,
      Ecto.Migrator,
      Oban,
      Plug,
      # The DSL loader's two adopted libraries (ORC-5, systems/core_dsl.md):
      # YAML parsing for bundle content, and libgraph for the type-level
      # acyclicity checks §13 requires at load time.
      Graph,
      YamlElixir,
      # The ES store family's machinery (v5 §2.4, systems/engine.md):
      # Commanded itself, its Postgres event store adapter, the
      # underlying EventStore library, and their own transitive
      # dependencies that contribute Elixir modules a `:prod` build can
      # reach (`fsm`, `gen_stage`, `telemetry_registry` — mix.exs's own
      # boundary apps list names the same set, for the same reason).
      Commanded,
      # `Catapult.Engine.Projections.RunFailures` already calls
      # `Commanded.EventStore.stream_forward/3` directly (the event
      # log's own read API, per its moduledoc) — a pre-existing gap
      # this entry closes rather than introduces: `mix compile
      # --warnings-as-errors` only re-checks a file's boundary
      # compliance when something about the boundary config changes,
      # so this stayed uncaught until this ticket's own edits to this
      # file invalidated the cache and surfaced it (a `"project"`
      # finding, filed separately).
      Commanded.EventStore,
      Commanded.EventStore.Adapters.EventStore,
      EventStore,
      Fsm,
      GenStage,
      TelemetryRegistry,
      # `@derive Jason.Encoder` on every versioned event struct
      # (Commanded's serializer needs it for the persistent adapter) —
      # `jason` is already a runtime dep, this is its first direct
      # reference from plane code. `Jason` itself (encode!/decode) is
      # the host port's own wire format (`Catapult.Delivery.Dispatch`).
      Jason,
      Jason.Encoder,
      # The host port's Actions adapter (ORC-9, systems/delivery.md):
      # the blessed HTTP client, `only: :test` no longer (mix.exs).
      Req,
      # GitHub Actions OIDC verification (ORC-9, v5 §7.12.1): stock
      # joken/joken_jwks machinery, no custom crypto
      # (`Catapult.Delivery.Oidc`).
      Joken,
      Joken.Config,
      Joken.Hooks,
      Joken.Signer,
      JokenJwks,
      JokenJwks.DefaultStrategyTemplate,
      JokenJwks.SignerMatchStrategy,
      # Liquid prompt rendering (ORC-9, `dsl-syntax.md` §9): context
      # assembly's own templating library (`Catapult.Generation
      # .ContextAssembly`).
      Solid,
      # `Catapult.Storybook.Screens.*`'s presentational shells
      # (`storybook/screens/**`, ORC-35, `systems/dashboard.md`'s
      # placement decision): stateless `Phoenix.Component`s compiled
      # under the coarse boundary the same as everything else, since
      # there is exactly one boundary today. Each entry is a distinct
      # implicit boundary `~H` compilation reaches into, the same
      # granularity `Ecto`'s four entries above are already at.
      Phoenix.Component,
      Phoenix.Component.Declarative,
      Phoenix.LiveView.Comprehension,
      Phoenix.LiveView.Engine,
      Phoenix.LiveView.HTMLEngine,
      Phoenix.LiveView.LiveStream,
      Phoenix.LiveView.Rendered,
      Phoenix.LiveView.TagEngine,
      # `Catapult.Storybook.Screens.*Story` modules (`storybook/screens/**`'s
      # `.story.exs` half): `phoenix_storybook` compiles them itself, at
      # `CatapultWeb.Storybook`'s own compile time, to build its content
      # tree — a reach into the coarse boundary from outside it, same as
      # every dep above.
      PhoenixStorybook
    ],
    exports: [
      # `CatapultWeb`'s read surface into the coarse boundary — the
      # same modules `lib/catapult/generation/**` and
      # `lib/catapult/delivery/**` already call directly for reads, no
      # boundary-export indirection (ORC-35's research: neither system
      # goes through a `defexport`'d function for this). `Foundation
      # .DispatchPlug` is exported so `CatapultWeb.Endpoint` can mount
      # it as a plug (`systems/foundation.md`'s design pass — the two
      # mechanisms share one listener).
      Storybook.Screens.EventLog,
      Storybook.Screens.ExplainWhy,
      Foundation.DispatchPlug,
      Engine.Store,
      Engine.Events,
      Engine.Application,
      Engine.Projections.ReadyScopes,
      Dsl,
      # ORC-75's own additions — the work surface's four v1 screens
      # (`systems/dashboard.md`). Presentational shells, the same
      # unindirected pattern the two above already establish:
      Storybook.Screens.MyQueue,
      Storybook.Screens.Board,
      Storybook.Screens.Ticket,
      Storybook.Screens.DocumentReview,
      # This system's first write path (`docs/ui-spec.md` §2's rule 1 —
      # a screen dispatches a command, never applies one itself):
      # `Engine.Router.dispatch/2` and the command structs a LiveView's
      # `handle_event` constructs directly, the identical "no
      # boundary-export indirection for a struct/function this
      # codebase already calls directly elsewhere" reasoning the read
      # side above takes.
      Engine.Router,
      Engine.Commands.ApproveGate,
      Engine.Commands.DeclineGate,
      Engine.Commands.ResumeFlow,
      Engine.Commands.PostComment,
      # Read surface the four screens need beyond `Engine.Store`/
      # `Engine.Events`/`Dsl` above: the feature-ticket lifecycle
      # projection and its effective-sequence reader (`board`/`ticket`),
      # the two log-position/log-fold reads `document-review`'s decline
      # path and comment list need, one event struct `board`/`ticket`
      # read the log for directly (`CatapultWeb.Live.EventFacts`'s own
      # "no flavor column exists yet" note), and the loaded workflow's
      # own gate declaration (`CatapultWeb.Live.Positions.role/2`).
      Delivery.Store,
      Delivery.FeatureLifecycle,
      Delivery.FeatureLifecycle.Sequence,
      Engine.Projections.GateComments,
      Engine.Projections.CommentFeedback,
      Engine.Events.RunFailed,
      Dsl.Workflow
    ]
end
