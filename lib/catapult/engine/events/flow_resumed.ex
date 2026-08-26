defmodule Catapult.Engine.Events.FlowResumed do
  @moduledoc """
  A human resumed a limit-class-blocked flow at a chosen position (v5
  §7.16, `systems/engine.md`'s ORC-114 design pass). Version 1.

  `to_kind`/`to_gate` carry the resolved
  `Catapult.Delivery.FeatureLifecycle.Sequence.position()` the command
  edge chose — never both set, never both nil, the identical flattened
  shape `Catapult.Delivery.Store.FeatureLifecycle`'s own
  `status_kind`/`status_gate` columns already use for this exact type.
  Flattened rather than carried as the bare `{:kind, atom()} | {:gate,
  String.t()}` tuple `Catapult.Engine.Commands.ResumeFlow.to` holds:
  `Commanded.Serialization.JsonSerializer` round-trips this struct's
  own fields through `Jason`, which has no `Encoder` for a raw tuple
  (confirmed by reproduction — `Jason.encode/1` on a tuple raises
  `Protocol.UndefinedError`), so a bare tuple field would crash event
  persistence on the first real (non-`InMemory`) dispatch. Two nullable
  strings need no such encoder, and `Catapult.Delivery.FeatureLifecycle`'s
  own `apply/2` clause for this event reconstructs the position from
  them with no workflow load, unlike its `GateDeclined` clause — a
  local, workflow-free match on which of the two is set, not a lookup.
  """

  @enforce_keys [:project_id, :flow_id]
  @derive Jason.Encoder
  defstruct [:project_id, :flow_id, :to_kind, :to_gate, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          to_kind: String.t() | nil,
          to_gate: String.t() | nil,
          actor_id: binary() | nil
        }
end
