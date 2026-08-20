defmodule Catapult.Engine.Events.RunFailed do
  @moduledoc """
  A dispatched agent run failed on a limit-class error (v5 §7.15,
  `systems/generation.md`). Version 1.

  Lands in the same per-project stream `DraftCommitted` already
  writes to — one aggregate per project, not one per system
  (`systems/generation.md`'s own design note) — which is what lets
  `Catapult.Engine.Projections.RunFailures` walk one log for both
  facts. The struct lives in this namespace rather than
  `Catapult.Generation.Events`, deliberately: `Catapult.Engine
  .Aggregate` is the only module that may construct an event landing
  in the per-project Commanded stream (dispatch-guard, v5 §7.16), and
  `Catapult.Generation` already depends on `Catapult.Engine`
  (`ready_scopes`, commands) — an aggregate importing a struct from
  its own consumer would close a dependency cycle the compile-
  connected ratchet (conventions §2) and `mix xref graph --format
  cycles` both refuse. Ownership of the *fact* is generation's (the
  executor decides when a run failed and why); ownership of the
  *stream it lands on* is engine's, structurally, and the struct
  follows the stream.

  `reason` is a short machine-readable tag for the limit-class error
  (e.g. `"usage_limit"`, `"rate_limit"`) — never the provider's raw
  message, which is visible-log territory the same way every other
  event payload here stays free of it.
  """

  @enforce_keys [:project_id, :node_id, :tier, :scope_key, :run_id, :reason, :occurred_at]
  @derive Jason.Encoder
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

  @type t :: %__MODULE__{
          project_id: binary(),
          node_id: binary(),
          tier: String.t(),
          scope_key: map(),
          run_id: binary(),
          reason: String.t(),
          occurred_at: DateTime.t(),
          actor_id: binary() | nil
        }
end
