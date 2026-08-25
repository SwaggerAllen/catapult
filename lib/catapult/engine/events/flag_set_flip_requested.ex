defmodule Catapult.Engine.Events.FlagSetFlipRequested do
  @moduledoc """
  The **intent** half of a milestone's aggregated flag flip (v5 §2.10,
  §7.8; §7.1's intent → idempotent effect → observed completion).
  Version 1.

  "'Shipping' a milestone aggregates the flag set from its included
  features and flips it… after the author's pass and a green live run
  — features merge dark as they complete; the milestone lights up
  together." `flags` is that aggregate: the union across this
  container's member work items, computed once and frozen onto the
  event, never re-derived on read.

  This event is not the flip. Enabling a flag is an external effect
  exactly like a GitHub call, so it may not share a transaction with
  an event (§7.1): this records that the plane means to flip,
  `Catapult.Delivery.FlagSetWorker` performs it idempotently, and
  `Catapult.Engine.Events.FlagSetFlipped` records the world's
  confirmation. The log never says "done" on the plane's own word.
  """

  @enforce_keys [:project_id, :container_id, :request_id, :flags]
  @derive Jason.Encoder
  defstruct [:project_id, :container_id, :request_id, :flags, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          request_id: binary(),
          flags: [String.t()],
          actor_id: binary() | nil
        }
end
