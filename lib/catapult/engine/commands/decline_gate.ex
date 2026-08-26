defmodule Catapult.Engine.Commands.DeclineGate do
  @moduledoc """
  A human's throwback on a declared workflow gate (v5 §7.16,
  `systems/engine.md`'s ORC-34 design pass, corrected on design
  review; given a compare-and-swap at ORC-114). Aggregate id:
  `project_id`.

  `gate`, `throwback_to` and `flow_id` are validated at the command
  edge against the loaded `Catapult.Dsl.Workflow.t()` before dispatch
  — the same division every other command on this aggregate already
  draws (`Catapult.Engine.Aggregate`'s own moduledoc: bundle content is
  the command edge's to check, never the aggregate's; a garbage
  `throwback_to` is the command edge's bug to have let through, not a
  malformed sequence for the aggregate to catch).

  `since_sequence` is caller-supplied — populated from `Catapult.Engine
  .Projections.GateComments.last_resolution_sequence(project_id, gate)`
  at the command-construction boundary, outside the aggregate, per this
  system's purity floor (`execute/2` may not read the log to compute
  it). The aggregate's own check is a different, pure one: at least one
  comment must have landed since `gate`'s own last resolution, answered
  from the aggregate's own state (`Catapult.Engine.Projections
  .GateComments.any_since_last_resolution?/2`'s retired store read moved
  here) — no free-text override, per `docs/ui-spec.md` §3.2's throwback
  action having a target and nothing else.

  `node_id` and `body_sha` are `ApproveGate`'s own new pair (ORC-114) —
  see its moduledoc for why: a decline against a body the aggregate has
  already moved past is exactly as stale as an approval against one.
  """

  @enforce_keys [
    :project_id,
    :flow_id,
    :gate,
    :throwback_to,
    :since_sequence,
    :node_id,
    :body_sha
  ]
  defstruct [
    :project_id,
    :flow_id,
    :gate,
    :throwback_to,
    :since_sequence,
    :node_id,
    :body_sha,
    :actor_id
  ]
end
