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
  compile error for every Elixir client and an audit check for the Erlang
  ones (`systems/substrate.md`). Naming which half is which is the
  difference between a gate and a belief about a gate.
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
      Plug
    ],
    exports: []
end
