defmodule Catapult.Engine.Commands.ApproveGate do
  @moduledoc """
  A human's sign-off on a declared workflow gate (v5 §7.16,
  `systems/engine.md`'s ORC-34 design pass, given a compare-and-swap
  at ORC-114). Aggregate id: `project_id`.

  `gate` and `flow_id` are validated at the command edge against the
  loaded `Catapult.Dsl.Workflow.t()` before dispatch — the same
  division every other command on this aggregate already draws (`
  Catapult.Engine.Aggregate`'s own moduledoc: bundle content is the
  command edge's to check, never the aggregate's). Role authorization
  (does `actor_id` hold `gate.role`) is left exactly where §7.16
  already leaves grant evaluation — identity's, a Phase 7 component.

  `node_id` and `body_sha` are `PostComment`'s own pair, carried here
  for the identical reason: the aggregate rejects a resolution whose
  view is a body it has already moved past, the same way it rejects a
  stale comment. Phase 4's own shipped `feature.yaml` runs exactly one
  `generation` status ahead of its gates, so there is exactly one node
  to read `body_sha` off; the general node(s)-per-gate mapping is
  Phase 7's, unchanged by this entry.
  """

  @enforce_keys [:project_id, :flow_id, :gate, :node_id, :body_sha]
  defstruct [:project_id, :flow_id, :gate, :node_id, :body_sha, :actor_id]
end
