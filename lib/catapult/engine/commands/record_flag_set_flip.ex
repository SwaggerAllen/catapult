defmodule Catapult.Engine.Commands.RecordFlagSetFlip do
  @moduledoc """
  Records the world's confirmation that a requested flag set is on (v5
  §7.1's observed completion). Aggregate id: `project_id`.

  Dispatched only from `Catapult.Delivery.FlagSetWorker`, after the
  flag port returns — never by whatever requested the flip.
  """

  @enforce_keys [:project_id, :container_id, :request_id, :flags]
  defstruct [:project_id, :container_id, :request_id, :flags]
end
