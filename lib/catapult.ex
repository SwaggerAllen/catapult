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
      Commanded.EventStore.Adapters.EventStore,
      EventStore,
      Fsm,
      GenStage,
      TelemetryRegistry,
      # `@derive Jason.Encoder` on every versioned event struct
      # (Commanded's serializer needs it for the persistent adapter) —
      # `jason` is already a runtime dep, this is its first direct
      # reference from plane code.
      Jason.Encoder
    ],
    exports: []
end
