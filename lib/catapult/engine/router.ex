defmodule Catapult.Engine.Router do
  @moduledoc """
  Routes every command straight to `Catapult.Engine.Aggregate` (v4
  §A.3.1). Dispatched directly — `Catapult.Engine.Router.dispatch/1,2`
  — rather than through `Catapult.Engine.Application`, which does not
  compose this module (see its own moduledoc for why).

  `@aggregate` is built with `Module.concat/1` rather than written as
  a plain alias. Not obfuscation: `identify/2` and `dispatch/2` are
  macros, and Elixir's compiler conservatively treats *any* literal
  module alias passed as a macro argument as a compile-time
  dependency on that module, whether or not the macro's expansion
  actually needs it compiled first (neither does here — both only
  store the atom in a module attribute for `Catapult.Engine.Aggregate`
  is read at dispatch time, not compiled). `Module.concat/1` produces
  the identical atom from a plain function call instead of an alias
  node, which is what keeps this router off the compile-connected
  graph the same way `Catapult.Engine.children/0`'s literal module
  references (ordinary function-body atoms, not macro arguments) stay
  off it.
  """

  use Commanded.Commands.Router, application: Catapult.Engine.Application

  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.CompleteFlow
  alias Catapult.Engine.Commands.DiscardDraft
  alias Catapult.Engine.Commands.FlipActiveBundle
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.WriteReview

  @aggregate Module.concat([Catapult, Engine, Aggregate])

  identify(@aggregate, by: :project_id, prefix: "project-")

  dispatch(
    [
      OpenFlow,
      CompleteFlow,
      CommitDraft,
      ApproveDraft,
      DiscardDraft,
      WriteReview,
      FlipActiveBundle
    ],
    to: @aggregate
  )
end
