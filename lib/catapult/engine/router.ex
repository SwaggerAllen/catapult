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

  alias Catapult.Engine.Commands.ActivateContainer
  alias Catapult.Engine.Commands.AdjudicateFinding
  alias Catapult.Engine.Commands.AdvanceContainerQueue
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.ApproveGate
  alias Catapult.Engine.Commands.CloseContainer
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.CompleteFlow
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.DiscardDraft
  alias Catapult.Engine.Commands.FlipActiveBundle
  alias Catapult.Engine.Commands.MintContainer
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Commands.RecordFlagSetFlip
  alias Catapult.Engine.Commands.RecordRunFailure
  alias Catapult.Engine.Commands.RequestFlagSetFlip
  alias Catapult.Engine.Commands.ResumeFlow
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
      FlipActiveBundle,
      RecordRunFailure,
      # ORC-104's container edge. Same aggregate, same router, same
      # per-project stream — `systems/engine.md`'s "a project has one
      # aggregate, not two." What is new is only the *direction* of the
      # writer: `Catapult.Delivery.ContainerLifecycle` is the first
      # process manager outside this system to dispatch here, which is
      # the split `systems/delivery.md` states from the other side
      # (engine is state of record, delivery is the protocol
      # interpreting it).
      MintContainer,
      ActivateContainer,
      AdvanceContainerQueue,
      CloseContainer,
      AdjudicateFinding,
      RequestFlagSetFlip,
      RecordFlagSetFlip,
      # ORC-34's decline-harvesting edge: a human comment, and the two
      # gate sign-off commands `Catapult.Delivery.FeatureLifecycle`
      # reacts to (`systems/engine.md`). Same aggregate, same router,
      # same per-project stream as every command above.
      PostComment,
      ApproveGate,
      DeclineGate,
      # ORC-114's unblock edge: the human resume `FeatureLifecycle
      # .Projection`'s own moduledoc names as missing. Same aggregate,
      # same router, same per-project stream as every command above.
      ResumeFlow
    ],
    to: @aggregate
  )
end
