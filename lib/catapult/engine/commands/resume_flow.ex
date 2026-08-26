defmodule Catapult.Engine.Commands.ResumeFlow do
  @moduledoc """
  A human's resume of a limit-class-blocked flow — the write
  `Catapult.Delivery.FeatureLifecycle.Projection`'s own moduledoc
  names as missing: "a block clears only via a subsequent
  `DraftCommitted` retry — never a human action" (v5 §7.16,
  `systems/engine.md`'s ORC-114 design pass). Aggregate id:
  `project_id`.

  `to` is the chosen return position, already resolved to
  `Catapult.Delivery.FeatureLifecycle.Sequence.position()`'s shape by
  the command edge that builds this command — validated there against
  the effective-sequence prefix up to and including the ticket's own
  `blocked_origin`, never forward (`docs/ui-spec.md` §6), the same
  division every other command on this aggregate already draws:
  bundle- and projection-derived content is checked before dispatch,
  never inside `execute/2`. Role authorization (does `actor_id` own
  the blocked ticket's origin status) is left exactly where every
  other gate-adjacent command already leaves it — identity's, Phase 7.
  """

  @enforce_keys [:project_id, :flow_id, :to]
  defstruct [:project_id, :flow_id, :to, :actor_id]
end
