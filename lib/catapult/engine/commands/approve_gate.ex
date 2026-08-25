defmodule Catapult.Engine.Commands.ApproveGate do
  @moduledoc """
  A human's sign-off on a declared workflow gate (v5 §7.16,
  `systems/engine.md`'s ORC-34 design pass). Aggregate id:
  `project_id`.

  `gate` and `flow_id` are validated at the command edge against the
  loaded `Catapult.Dsl.Workflow.t()` before dispatch — the same
  division every other command on this aggregate already draws (`
  Catapult.Engine.Aggregate`'s own moduledoc: bundle content is the
  command edge's to check, never the aggregate's). Role authorization
  (does `actor_id` hold `gate.role`) is left exactly where §7.16
  already leaves grant evaluation — identity's, a Phase 7 component.
  """

  @enforce_keys [:project_id, :flow_id, :gate]
  defstruct [:project_id, :flow_id, :gate, :actor_id]
end
