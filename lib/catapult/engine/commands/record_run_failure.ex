defmodule Catapult.Engine.Commands.RecordRunFailure do
  @moduledoc """
  Records a limit-class dispatch-run failure against a scope's node
  (`systems/generation.md`, v5 §7.15). Dispatched by the generation
  executor's command edge — never engine's own code — the same way
  `CommitDraft` is: every id and timestamp is supplied by the caller,
  none generated here (the purity floor, `systems/engine.md`).

  This is the fact `Catapult.Engine.Projections.RunFailures` derives
  its count from: `Catapult.Generation`'s executor stops redispatching
  a scope once that derived count repeats past one (§7.15's "never
  another retry"), rather than holding a counter of its own.
  """

  @enforce_keys [:project_id, :node_id, :tier, :scope_key, :run_id, :reason, :occurred_at]
  defstruct [
    :project_id,
    :node_id,
    :tier,
    :scope_key,
    :run_id,
    :reason,
    :occurred_at,
    :actor_id
  ]
end
