defmodule Catapult.Engine.Events.FlagSetFlipped do
  @moduledoc """
  The **observed completion** half of a milestone's aggregated flag
  flip (v5 §7.1, §7.8). Version 1: the world confirmed every flag in
  the requested set is on.

  Written only by `Catapult.Delivery.FlagSetWorker`, after the flag
  port returns — never by whatever decided to flip. An
  intent-without-effect is visible in the projection (a container
  sitting at `:requested`) and escalates; an effect-without-record
  heals by re-observation, since the worker's enable is idempotent.
  """

  @enforce_keys [:project_id, :container_id, :request_id, :flags]
  @derive Jason.Encoder
  defstruct [:project_id, :container_id, :request_id, :flags]

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          request_id: binary(),
          flags: [String.t()]
        }
end
